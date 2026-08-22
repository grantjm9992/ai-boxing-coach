import 'package:flutter/foundation.dart';

import '../analysis/analysis_mode.dart';
import '../analysis/drill.dart';
import '../analysis/pose_only_adapter.dart';
import '../analysis/round_analysis.dart';
import '../domain/round_clip.dart';
import 'ai/coaching_prompt.dart';
import 'ai/vision_model.dart';
import 'analysis_store.dart';
import 'frame_grabber.dart';
import 'pose_estimator.dart';

/// Runs the analysis pipeline over a recorded round and persists the result.
///
/// Always runs pose + the rule engine on-device (that gives the metrics, the
/// review skeleton and the base coaching, for free). In the AI modes it then
/// layers a vision model's read on top:
///  - [AnalysisMode.keyframe] sends the handful of frames the rules flagged;
///  - [AnalysisMode.fullFrame] sends frames sampled across the whole round.
///
/// Everything AI is best-effort: no model, no key, no network → the round still
/// has its offline rules analysis. Coaching is additive, never a blocker.
class RoundAnalyzer {
  RoundAnalyzer({
    PoseEstimator? estimator,
    AnalysisStore? store,
    PoseOnlyAdapter? adapter,
    this.visionModel,
    this.frameGrabber,
  }) : _estimator = estimator ?? MediaPipePoseEstimator(),
       _store = store ?? AnalysisStore(),
       _adapter = adapter ?? PoseOnlyAdapter();

  final PoseEstimator _estimator;
  final AnalysisStore _store;
  final PoseOnlyAdapter _adapter;
  final VisionModel? visionModel;
  final FrameGrabber? frameGrabber;

  Future<RoundAnalysis?> analyse(
    RoundClip clip, {
    DrillContext? drill,
    AnalysisMode mode = AnalysisMode.offline,
  }) async {
    try {
      PoseAnalysisResult? result;
      // Guard against a native pose stream that stalls without erroring or
      // closing (seen on release builds): a gap this long between updates means
      // something is wrong — fail the round rather than hang it forever. The
      // timeout is per-event, so a slow-but-progressing run is unaffected.
      final stream = _estimator
          .analyse(clip.path)
          .timeout(const Duration(seconds: 45));
      await for (final progress in stream) {
        if (progress.result != null) result = progress.result;
      }
      if (result == null) return null;

      final resolvedDrill = drill ?? const DrillContext();
      var analysis = _adapter.analyse(result.sequence, resolvedDrill);

      if (mode.usesAi && visionModel != null && frameGrabber != null) {
        final coaching = await _aiCoaching(
          mode,
          clip,
          analysis,
          resolvedDrill,
          result.sequence.durationMs,
        );
        if (coaching != null && coaching.trim().isNotEmpty) {
          analysis = analysis.withModelCoaching(coaching.trim());
        }
      }

      await _store.save(
        clip.sessionId,
        clip.segmentIndex,
        analysis: analysis,
        sequence: result.sequence,
      );
      return analysis;
    } on Object catch (error) {
      debugPrint('Round analysis failed for ${clip.path}: $error');
      return null;
    }
  }

  Future<String?> _aiCoaching(
    AnalysisMode mode,
    RoundClip clip,
    RoundAnalysis analysis,
    DrillContext drill,
    double durationMs,
  ) async {
    try {
      final timestamps = mode == AnalysisMode.keyframe
          ? CoachingPrompt.keyframeTimestamps(analysis)
          : CoachingPrompt.sampledTimestamps(durationMs);
      if (timestamps.isEmpty) return null;

      final images = await frameGrabber!.grab(clip.path, timestamps);
      if (images.isEmpty) return null;

      final request = mode == AnalysisMode.keyframe
          ? CoachingPrompt.keyframeRequest(analysis, drill, images)
          : CoachingPrompt.fullFrameRequest(drill, images);
      return await visionModel!.complete(request);
    } on VisionModelException catch (error) {
      debugPrint('AI coaching unavailable: ${error.message}');
      return null;
    } on Object catch (error) {
      debugPrint('AI coaching failed: $error');
      return null;
    }
  }
}
