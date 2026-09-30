import 'dart:convert';
import 'dart:io';

import 'package:boxing_coach/analysis/analysis_mode.dart';
import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/analysis/pose_only_adapter.dart';
import 'package:boxing_coach/domain/round_clip.dart';
import 'package:boxing_coach/domain/session_phase.dart';
import 'package:boxing_coach/services/ai/video_vision_model.dart';
import 'package:boxing_coach/services/analysis_store.dart';
import 'package:boxing_coach/services/background_analysis.dart';
import 'package:boxing_coach/services/round_coach.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_support.dart';

/// A combination drill is analysed on the spot (pose + rules + checkpoints);
/// in an AI mode its AI review then runs in the background over that saved
/// analysis — no second tracking pass — and is saved back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final goldenDir = locateGoldenDir();
  if (goldenDir == null) {
    test('golden fixtures present', () => fail('run emit_golden_fixtures.py'));
    return;
  }

  const drill = DrillContext(targetSequence: <int>[1], notes: '1');
  final sequence = PoseSequence.fromJson(
    jsonDecode(
      File('${goldenDir.path}/dropped_guard_jab/input.json').readAsStringSync(),
    ) as Map<String, Object?>,
  );
  final clip = RoundClip(
    sessionId: 'drill_1',
    segmentIndex: 0,
    phase: SessionPhase.technical,
    path: '/clips/drill_1_seg0.mp4',
    recordedAt: DateTime(2026, 9, 30),
    targetSequence: const <int>[1],
  );

  late Directory dir;
  late AnalysisStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('drill_ai_review');
    store = AnalysisStore(baseDir: dir);
    // What the drill screen saved: the on-the-spot analysis and the pose.
    await store.save(
      clip.sessionId,
      clip.segmentIndex,
      analysis: PoseOnlyAdapter().analyse(sequence, drill),
      sequence: sequence,
    );
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  FakeVideoVisionModel videoModel() => FakeVideoVisionModel(
        response: jsonEncode(<String, Object?>{
          'summary': 'The jab hangs out there. Snap it back.',
          'strengths': <String>['Good stance'],
          'priority_issues': <Object?>[
            <String, Object?>{
              'code': 'REC_001',
              'severity': 'HIGH',
              'confidence': 0.9,
              'timestamps': <double>[0.6],
              'observation': 'Your jab lingers after it lands.',
              'correction': 'Snap it back to your face.',
              'checkpoint': 'jab_snap_back',
            },
          ],
        }),
      );

  test('Full AI review of a drill: the checkpoints go to the model and the '
      'enriched analysis is saved back', () async {
    final model = videoModel();

    final enriched = await BackgroundAnalysis.instance.reviewWithAi(
      clip,
      drill: drill,
      store: store,
      coach: RoundCoach(videoModel: model),
      mode: AnalysisMode.fullFrame,
    );

    expect(model.requests, hasLength(1));
    expect(model.requests.single.userPrompt,
        contains('This round is a drill of 1'));
    expect(model.requests.single.userPrompt, contains('[jab_snap_back]'));

    expect(enriched, isNotNull);
    expect(enriched!.aiReport!.priorityIssues.single.checkpoint,
        'jab_snap_back');
    // The on-device checkpoint tallies are kept.
    expect(enriched.checkpointTallies.single.checkpoint.id, 'jab_snap_back');

    final saved = await store.loadAnalysis(clip.sessionId, clip.segmentIndex);
    expect(saved!.modelCoaching, 'The jab hangs out there. Snap it back.');
    expect(saved.checkpointTallies, hasLength(1));

    // Nothing left marked as running.
    expect(BackgroundAnalysis.instance.isRunning(clip), isFalse);
    expect(BackgroundAnalysis.instance.progressFor(clip), isNull);
  });

  test('offline mode leaves the drill alone', () async {
    final model = videoModel();
    final enriched = await BackgroundAnalysis.instance.reviewWithAi(
      clip,
      drill: drill,
      store: store,
      coach: RoundCoach(videoModel: model),
      mode: AnalysisMode.offline,
    );
    expect(enriched, isNull);
    expect(model.requests, isEmpty);
    final saved = await store.loadAnalysis(clip.sessionId, clip.segmentIndex);
    expect(saved!.modelCoaching, isNull);
  });

  test('a round with nothing saved is skipped', () async {
    final model = videoModel();
    final enriched = await BackgroundAnalysis.instance.reviewWithAi(
      RoundClip(
        sessionId: 'drill_missing',
        segmentIndex: 0,
        phase: SessionPhase.technical,
        path: '/clips/missing.mp4',
        recordedAt: DateTime(2026, 9, 30),
      ),
      drill: drill,
      store: store,
      coach: RoundCoach(videoModel: model),
      mode: AnalysisMode.fullFrame,
    );
    expect(enriched, isNull);
    expect(model.requests, isEmpty);
  });

  test('an unusable AI reply keeps the on-device analysis', () async {
    final enriched = await BackgroundAnalysis.instance.reviewWithAi(
      clip,
      drill: drill,
      store: store,
      coach: RoundCoach(videoModel: FakeVideoVisionModel(response: 'nice')),
      mode: AnalysisMode.fullFrame,
    );
    expect(enriched, isNull);
    final saved = await store.loadAnalysis(clip.sessionId, clip.segmentIndex);
    expect(saved!.modelCoaching, isNull);
    expect(saved.checkpointTallies.single.failed, 1);
    expect(BackgroundAnalysis.instance.isRunning(clip), isFalse);
  });
}
