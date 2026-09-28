import 'dart:convert';
import 'dart:io';

import 'package:boxing_coach/analysis/analysis_mode.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/domain/round_clip.dart';
import 'package:boxing_coach/domain/session_phase.dart';
import 'package:boxing_coach/services/ai/coaching_prompt.dart';
import 'package:boxing_coach/services/ai/video_vision_model.dart';
import 'package:boxing_coach/services/ai/vision_model.dart';
import 'package:boxing_coach/services/analysis_store.dart';
import 'package:boxing_coach/services/frame_grabber.dart';
import 'package:boxing_coach/services/pose_estimator.dart';
import 'package:boxing_coach/services/round_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pose_landmarker/pose_landmarker.dart';

import 'golden_support.dart';

/// A pose estimator that just replays a fixed sequence — no plugin, no device.
class _FakeEstimator implements PoseEstimator {
  _FakeEstimator(this.sequence);
  final PoseSequence sequence;

  @override
  Stream<PoseAnalysisProgress> analyse(
    String videoPath, {
    Duration sampleEvery = const Duration(milliseconds: 33),
    PoseModel model = PoseModel.lite,
  }) async* {
    yield const PoseAnalysisProgress(fraction: 0.5);
    yield PoseAnalysisProgress(
      fraction: 1,
      result: PoseAnalysisResult(
        sequence: sequence,
        framesAnalysed: sequence.length,
        fullBodyVisibleFraction: 1,
        elapsed: Duration.zero,
      ),
    );
  }
}

void main() {
  final goldenDir = locateGoldenDir();
  if (goldenDir == null) {
    test('golden fixtures present', () => fail('run emit_golden_fixtures.py'));
    return;
  }

  // dropped_guard_jab produces a guard-return fault (a flagged moment) so the
  // keyframe path has something to send.
  final sequence = PoseSequence.fromJson(
    jsonDecode(
      File('${goldenDir.path}/dropped_guard_jab/input.json').readAsStringSync(),
    ) as Map<String, Object?>,
  );

  late Directory tempDir;
  late AnalysisStore store;
  late FakeVisionModel model;
  late FakeFrameGrabber grabber;
  late RoundAnalyzer analyzer;

  final clip = RoundClip(
    sessionId: 's1',
    segmentIndex: 0,
    phase: SessionPhase.technical,
    path: '/does/not/matter.mp4',
    recordedAt: DateTime(2026, 8, 18),
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('analyzer_test');
    store = AnalysisStore(baseDir: tempDir);
    model = FakeVisionModel(response: 'AI: snap the jab straight back.');
    grabber = FakeFrameGrabber();
    analyzer = RoundAnalyzer(
      estimator: _FakeEstimator(sequence),
      store: store,
      visionModel: model,
      frameGrabber: grabber,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('offline mode runs rules only — no model call, no AI coaching', () async {
    final analysis = await analyzer.analyse(clip);

    expect(analysis, isNotNull);
    expect(analysis!.correctionPriorities, isNotEmpty); // the guard drop
    expect(analysis.modelCoaching, isNull);
    expect(model.requests, isEmpty);
    expect(grabber.calls, isEmpty);
  });

  test('keyframe mode sends the flagged moments and attaches AI coaching', () async {
    final analysis = await analyzer.analyse(clip, mode: AnalysisMode.keyframe);

    expect(analysis!.modelCoaching, 'AI: snap the jab straight back.');
    expect(model.requests, hasLength(1));
    // It grabbed a burst of frames around each rule-flagged moment — more than
    // the one-per-moment history set.
    expect(grabber.calls, hasLength(1));
    final bursts =
        CoachingPrompt.keyframeBursts(analysis, durationMs: sequence.durationMs);
    expect(grabber.calls.single, <double>[for (final b in bursts) ...b.timestamps]);
    expect(
      grabber.calls.single.length,
      greaterThan(CoachingPrompt.keyframeTimestamps(analysis).length),
    );
    expect(model.requests.single.images, isNotEmpty);
  });

  test('full AI review sends the whole video at 24 fps with the flagged points',
      () async {
    final video = FakeVideoVisionModel(response: 'Full: rear hand stays home.');
    final fullAnalyzer = RoundAnalyzer(
      estimator: _FakeEstimator(sequence),
      store: store,
      visionModel: model,
      frameGrabber: grabber,
      videoModel: video,
    );

    final analysis =
        await fullAnalyzer.analyse(clip, mode: AnalysisMode.fullFrame);

    expect(analysis!.modelCoaching, 'Full: rear hand stays home.');
    expect(video.requests, hasLength(1));
    final request = video.requests.single;
    expect(request.videoPath, clip.path);
    expect(request.fps, 24);
    expect(request.mimeType, 'video/mp4');
    // The same rule-flagged moments the review screen highlights are in the
    // prompt, so the model reviews those exact points.
    expect(request.userPrompt, contains('Flagged points'));
    // No frames grabbed and no image-model call: the video replaces them.
    expect(grabber.calls, isEmpty);
    expect(model.requests, isEmpty);
    // The highlighted errors come from the rules, exactly as in key-moment mode.
    expect(analysis.flaggedMoments, isNotEmpty);
  });

  test('full AI review with no video model falls back to key moments', () async {
    final analysis = await analyzer.analyse(clip, mode: AnalysisMode.fullFrame);

    expect(analysis!.modelCoaching, 'AI: snap the jab straight back.');
    expect(model.requests, hasLength(1));
    expect(grabber.calls, hasLength(1));
  });

  test('with no model configured, AI modes fall back to rules only', () async {
    final offlineAnalyzer = RoundAnalyzer(
      estimator: _FakeEstimator(sequence),
      store: store,
    );
    final analysis =
        await offlineAnalyzer.analyse(clip, mode: AnalysisMode.keyframe);
    expect(analysis!.modelCoaching, isNull);
    expect(analysis.correctionPriorities, isNotEmpty);
  });
}
