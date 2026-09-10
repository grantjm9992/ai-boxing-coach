// RoundAnalysis dumper for the evaluation platform.
//
// Runs the real Dart analysis engine (`PoseOnlyAdapter.analyse`) over a pose
// sequence and writes `RoundAnalysis.toJson()` per clip. This is the app's own
// CV engine — same rules, same fine `code` per observation — so the output is
// what the coaching layer would actually be given on-device. It matters because
// the Python `boxing-coach --json` only emits COARSE rule ids; the coaching
// prompt (and thus the coaching exporter) needs the fine codes this produces.
//
// The engine is pure Dart, but the on-device pose source (pose_landmarker
// plugin) has no headless runner. So the pose sequence is supplied as a
// `pose.json` (the shared golden-fixture wire format) produced by the Python
// estimator, which runs here:
//
//   boxing-coach clip.mp4 --dump-pose datasets/development/clip/pose.json
//
// Then this tool turns each pose.json into a `round_analysis.json` that
// export_coaching_predictions.dart consumes. Runs under `flutter test` and is
// GATED on DUMP_ANALYSIS=1 so an ordinary `flutter test` skips it.
//
// Run:
//   cd app
//   DUMP_ANALYSIS=1 flutter test test/tools/dump_round_analysis.dart
//
// Env:
//   DUMP_ANALYSIS   must be "1" or the test is skipped.
//   DATASET_DIR     clip dirs to scan     (default ../datasets/development)
//   POSE_FILE       pose json name per clip dir      (default pose.json)
//   ANALYSIS_FILE   output name per clip dir (default round_analysis.json)
//   ONLY            comma-separated video_ids to restrict to

import 'dart:convert';
import 'dart:io';

import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/analysis/pose_only_adapter.dart';
import 'package:boxing_coach/analysis/school.dart';
import 'package:boxing_coach/analysis/session_type.dart';
import 'package:flutter_test/flutter_test.dart';

String _env(String key, [String fallback = '']) =>
    Platform.environment[key]?.trim().isNotEmpty == true
        ? Platform.environment[key]!.trim()
        : fallback;

DrillContext _drillFrom(Map<String, Object?> context) {
  final stance = (context['stance'] as String?) == 'southpaw'
      ? Stance.southpaw
      : Stance.orthodox;
  final style = Style.values.firstWhere(
    (s) => s.value == context['style'] as String?,
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

void main() {
  test('dump round analysis', () {
    if (_env('DUMP_ANALYSIS') != '1') {
      markTestSkipped('set DUMP_ANALYSIS=1 to run the RoundAnalysis dumper');
      return;
    }

    final datasetDir = Directory(_env('DATASET_DIR', '../datasets/development'));
    final poseFile = _env('POSE_FILE', 'pose.json');
    final analysisFile = _env('ANALYSIS_FILE', 'round_analysis.json');
    final only = _env('ONLY')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    expect(datasetDir.existsSync(), isTrue,
        reason: 'DATASET_DIR not found: ${datasetDir.path}');

    final adapter = PoseOnlyAdapter();
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
      final videoId = (gt['video_id'] as String?) ??
          entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (only.isNotEmpty && !only.contains(videoId)) continue;

      final poseJson = File('${entry.path}/$poseFile');
      if (!poseJson.existsSync()) {
        skipped.add('$videoId (no $poseFile — run boxing-coach --dump-pose)');
        continue;
      }

      try {
        final sequence = PoseSequence.fromJson(
            (jsonDecode(poseJson.readAsStringSync()) as Map)
                .cast<String, Object?>());
        final drill = _drillFrom(
            (gt['context'] as Map?)?.cast<String, Object?>() ?? const {});
        final analysis = adapter.analyse(sequence, drill);
        File('${entry.path}/$analysisFile').writeAsStringSync(
            '${const JsonEncoder.withIndent('  ').convert(analysis.toJson())}\n');
        wrote.add(videoId);
      } catch (e, st) {
        failed.add('$videoId ($e)');
        stderr.writeln('$videoId trace:\n$st');
      }
    }

    stderr.writeln('wrote:   ${wrote.join(', ')}');
    if (skipped.isNotEmpty) stderr.writeln('skipped: ${skipped.join(', ')}');
    if (failed.isNotEmpty) stderr.writeln('failed:  ${failed.join(', ')}');
    stderr.writeln('${wrote.length} written, ${skipped.length} skipped, '
        '${failed.length} failed');

    expect(failed, isEmpty, reason: 'some clips failed to analyse');
    expect(wrote, isNotEmpty, reason: 'nothing written — check POSE_FILE');
  });
}
