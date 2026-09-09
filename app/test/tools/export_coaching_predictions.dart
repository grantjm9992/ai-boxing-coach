// Coaching-layer prediction exporter for the evaluation platform.
//
// This is the Dart half of eval "step 1": it produces `AiCoachReport` JSON for
// benchmark clips using the SAME prompt/model/parse path the app uses
// (`CoachingPrompt.structuredRequest` -> `VisionModel.complete` ->
// `AiCoachReport.tryParse`), then writes one `<video_id>.json` per clip. The
// Python `evaluation/predict.py --layer coaching --import-dir <EXPORT_DIR>`
// ingests those files into `predictions/<version>/coaching.json` for scoring.
//
// It runs under `flutter test` because the vision transport imports Flutter, so
// a plain `dart run` can't load it. It is GATED on EXPORT_COACHING=1 so an
// ordinary `flutter test` run skips it (no network, no writes).
//
// Why it takes a RoundAnalysis as input rather than a raw video: the on-device
// CV path (`RoundAnalysis`) is produced from the native pose_landmarker plugin,
// which has no headless runner. So the analysis for each clip is supplied as a
// `RoundAnalysis.toJson()` file next to the clip; generating that from a real
// clip is the remaining native step (dump it from the app, or a future
// headless pose bridge). Everything downstream of the analysis is exercised
// here for real.
//
// Run:
//   cd app
//   # offline plumbing check (canned model response, temp export dir):
//   EXPORT_COACHING=1 EXPORT_DIR=/tmp/coach \
//     flutter test test/tools/export_coaching_predictions.dart
//
//   # real predictions against the coaching proxy / an OpenAI-compatible API:
//   EXPORT_COACHING=1 \
//   COACH_BASE_URL=https://.../v1 COACH_API_KEY=sk-... COACH_MODEL=coach \
//   EXPORT_DIR=../evaluation/exports/coaching \
//     flutter test test/tools/export_coaching_predictions.dart
//
// Env:
//   EXPORT_COACHING  must be "1" or the test is skipped.
//   DATASET_DIR      clip dirs to scan       (default ../datasets/development)
//   EXPORT_DIR       where <video_id>.json go (default ../evaluation/exports/coaching)
//   ANALYSIS_FILE    RoundAnalysis json name under each clip dir (default round_analysis.json)
//   ONLY             comma-separated video_ids to restrict to
//   COACH_BASE_URL   OpenAI-compatible base url; empty -> FakeVisionModel
//   COACH_API_KEY    bearer token for the above
//   COACH_MODEL      model name             (default "coach")
//   FAKE_RESPONSE    canned model reply used when COACH_BASE_URL is empty

import 'dart:convert';
import 'dart:io';

import 'package:boxing_coach/analysis/ai_coach_report.dart';
import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/analysis/school.dart';
import 'package:boxing_coach/analysis/session_type.dart';
import 'package:boxing_coach/services/ai/coaching_prompt.dart';
import 'package:boxing_coach/services/ai/openai_compatible_vision_model.dart';
import 'package:boxing_coach/services/ai/vision_model.dart';
import 'package:boxing_coach/services/ai/vision_model_config.dart';
import 'package:flutter_test/flutter_test.dart';

String _env(String key, [String fallback = '']) =>
    Platform.environment[key]?.trim().isNotEmpty == true
        ? Platform.environment[key]!.trim()
        : fallback;

/// A schema-valid report used only for the offline (no COACH_BASE_URL) run, so
/// the export path can be verified end-to-end without a live model.
const String _defaultFakeResponse = '''
{"summary":"Offline export self-check — not a real coaching prediction.",
 "strengths":["clean guard return"],
 "priority_issues":[
   {"code":"GUARD_002","severity":"medium","confidence":0.6,"timestamps":[0.2],
    "observation":"Lead hand drifts down between punches.",
    "why_it_matters":"Open to the counter.",
    "correction":"Return the hand to the cheek after every shot.",
    "suggested_drill":"Jab-return shadow drill."}],
 "next_session_focus":["guard discipline"]}
''';

DrillContext _drillFrom(Map<String, Object?> context) {
  final stance = (context['stance'] as String?) == 'southpaw'
      ? Stance.southpaw
      : Stance.orthodox;
  final styleValue = context['style'] as String?;
  final style = Style.values.firstWhere(
    (s) => s.value == styleValue,
    orElse: () => Style.highGuard,
  );
  final sessionType = switch (context['exercise'] as String?) {
    'shadow' => SessionType.shadowBoxing,
    'bag' => SessionType.heavyBag,
    'drill' => SessionType.technicalWork,
    'combination' => SessionType.combinationDrill,
    _ => SessionType.freeTraining,
  };
  return DrillContext(
    stance: stance,
    style: style,
    school: School.fromValue(context['school'] as String?),
    sessionType: sessionType,
  );
}

VisionModel _resolveModel() {
  final baseUrl = _env('COACH_BASE_URL');
  if (baseUrl.isEmpty) {
    return FakeVisionModel(
        response: _env('FAKE_RESPONSE', _defaultFakeResponse));
  }
  return OpenAiCompatibleVisionModel(VisionModelConfig(
    baseUrl: baseUrl,
    apiKey: _env('COACH_API_KEY'),
    model: _env('COACH_MODEL', 'coach'),
    useCustomEndpoint: true,
  ));
}

void main() {
  test('export coaching predictions', () async {
    if (_env('EXPORT_COACHING') != '1') {
      markTestSkipped('set EXPORT_COACHING=1 to run the coaching exporter');
      return;
    }

    final datasetDir = Directory(_env('DATASET_DIR', '../datasets/development'));
    final exportDir = Directory(_env('EXPORT_DIR', '../evaluation/exports/coaching'));
    final analysisFile = _env('ANALYSIS_FILE', 'round_analysis.json');
    final only = _env('ONLY')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    expect(datasetDir.existsSync(), isTrue,
        reason: 'DATASET_DIR not found: ${datasetDir.path}');
    exportDir.createSync(recursive: true);
    final model = _resolveModel();
    final live = _env('COACH_BASE_URL').isNotEmpty;
    stderr.writeln('coaching export -> ${exportDir.path} '
        '(${live ? 'live model' : 'FakeVisionModel — offline check'})');

    final wrote = <String>[];
    final skipped = <String>[];
    final failed = <String>[];

    final clipDirs = datasetDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entry in clipDirs) {
      final gtFile = File('${entry.path}/ground_truth.json');
      if (!gtFile.existsSync()) continue;
      final gt = (jsonDecode(gtFile.readAsStringSync()) as Map)
          .cast<String, Object?>();
      final videoId = (gt['video_id'] as String?) ?? entry.uri.pathSegments
          .where((s) => s.isNotEmpty).last;
      if (only.isNotEmpty && !only.contains(videoId)) continue;

      final analysisPath = File('${entry.path}/$analysisFile');
      if (!analysisPath.existsSync()) {
        skipped.add('$videoId (no $analysisFile — supply a RoundAnalysis)');
        continue;
      }

      try {
        final analysis = RoundAnalysis.fromJson(
            (jsonDecode(analysisPath.readAsStringSync()) as Map)
                .cast<String, Object?>());
        final drill = _drillFrom(
            (gt['context'] as Map?)?.cast<String, Object?>() ?? const {});
        final request = CoachingPrompt.structuredRequest(analysis, drill);

        final raw = await model.complete(request);
        final report = AiCoachReport.tryParse(raw);
        if (report == null) {
          failed.add('$videoId (model reply did not match the report schema)');
          continue;
        }
        File('${exportDir.path}/$videoId.json')
            .writeAsStringSync('${const JsonEncoder.withIndent('  ')
                .convert(report.toJson())}\n');
        wrote.add(videoId);
      } on VisionModelException catch (e) {
        failed.add('$videoId (model error: ${e.message})');
      } catch (e) {
        failed.add('$videoId ($e)');
      }
    }

    stderr.writeln('wrote:   ${wrote.join(', ')}');
    if (skipped.isNotEmpty) stderr.writeln('skipped: ${skipped.join(', ')}');
    if (failed.isNotEmpty) stderr.writeln('failed:  ${failed.join(', ')}');
    stderr.writeln('${wrote.length} written, ${skipped.length} skipped, '
        '${failed.length} failed');

    expect(failed, isEmpty, reason: 'some clips failed to export');
    expect(wrote, isNotEmpty, reason: 'nothing exported — check ANALYSIS_FILE');
  });
}
