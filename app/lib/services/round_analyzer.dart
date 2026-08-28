import 'package:flutter/foundation.dart';

import '../analysis/ai_coach_report.dart';
import '../analysis/analysis_mode.dart';
import '../analysis/drill.dart';
import '../analysis/pose_only_adapter.dart';
import '../analysis/round_analysis.dart';
import '../domain/feature_flags.dart';
import '../domain/round_clip.dart';
import 'analytics.dart';
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
    Analytics? analytics,
    this.visionModel,
    this.frameGrabber,
  }) : _estimator = estimator ?? MediaPipePoseEstimator(),
       _store = store ?? AnalysisStore(),
       _adapter = adapter ?? PoseOnlyAdapter(),
       _analytics = analytics ?? AnalyticsScope.instance;

  final PoseEstimator _estimator;
  final AnalysisStore _store;
  final PoseOnlyAdapter _adapter;
  final Analytics _analytics;
  final VisionModel? visionModel;
  final FrameGrabber? frameGrabber;

  Future<RoundAnalysis?> analyse(
    RoundClip clip, {
    DrillContext? drill,
    AnalysisMode mode = AnalysisMode.offline,
  }) async {
    _analytics.log(AnalyticsEvent.analysisStarted,
        <String, Object?>{'mode': mode.value});
    try {
      PoseAnalysisResult? result;
      // The estimator serialises native runs and guards each against a stall
      // internally, so here we just consume progress.
      await for (final progress in _estimator.analyse(clip.path)) {
        if (progress.result != null) result = progress.result;
      }
      if (result == null) {
        _analytics.log(AnalyticsEvent.analysisFailed,
            <String, Object?>{'reason': 'no_pose'});
        return null;
      }

      final resolvedDrill = drill ?? const DrillContext();
      var analysis = _adapter.analyse(result.sequence, resolvedDrill);

      if (mode.usesAi && visionModel != null && frameGrabber != null) {
        if (FeatureFlags.advancedAiAnalysis && mode == AnalysisMode.fullFrame) {
          // Advanced path (brief §17/§18): structured measurements in, strict
          // JSON out. Unschematic output is rejected, not shown.
          _analytics.log(AnalyticsEvent.advancedAnalysisRequested);
          final report = await _advancedReport(
            clip,
            analysis,
            resolvedDrill,
            result.sequence.durationMs,
          );
          if (report != null) {
            analysis =
                analysis.withAiReport(report).withModelCoaching(report.summary);
          }
        } else {
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
      }

      await _store.save(
        clip.sessionId,
        clip.segmentIndex,
        analysis: analysis,
        sequence: result.sequence,
      );
      _analytics.log(AnalyticsEvent.analysisCompleted, <String, Object?>{
        'mode': mode.value,
        'combinations': analysis.combinations.length,
      });
      return analysis;
    } on Object catch (error) {
      debugPrint('Round analysis failed for ${clip.path}: $error');
      _analytics.log(AnalyticsEvent.analysisFailed,
          <String, Object?>{'reason': 'exception'});
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
      final VisionRequest request;
      if (mode == AnalysisMode.keyframe) {
        // A burst of frames around each flagged moment — motion context, not a
        // single still.
        final bursts =
            CoachingPrompt.keyframeBursts(analysis, durationMs: durationMs);
        final timestamps = <double>[for (final b in bursts) ...b.timestamps];
        if (timestamps.isEmpty) return null;
        final images = await frameGrabber!.grab(clip.path, timestamps);
        if (images.isEmpty) return null;
        request = CoachingPrompt.keyframeRequest(analysis, drill, bursts, images);
      } else {
        final timestamps = CoachingPrompt.sampledTimestamps(durationMs);
        if (timestamps.isEmpty) return null;
        final images = await frameGrabber!.grab(clip.path, timestamps);
        if (images.isEmpty) return null;
        request = CoachingPrompt.fullFrameRequest(drill, images);
      }
      return await visionModel!.complete(request);
    } on VisionModelException catch (error) {
      debugPrint('AI coaching unavailable: ${error.message}');
      return null;
    } on Object catch (error) {
      debugPrint('AI coaching failed: $error');
      return null;
    }
  }

  /// The advanced structured path: send the CV measurements (+ sampled frames)
  /// and require a schema-valid JSON report back. Returns null — no report,
  /// never fabricated coaching — if the model errors or the output doesn't
  /// validate (brief §18).
  Future<AiCoachReport?> _advancedReport(
    RoundClip clip,
    RoundAnalysis analysis,
    DrillContext drill,
    double durationMs,
  ) async {
    try {
      final timestamps = CoachingPrompt.sampledTimestamps(durationMs);
      final images = timestamps.isEmpty
          ? const <VisionImage>[]
          : await frameGrabber!.grab(clip.path, timestamps);
      final request = CoachingPrompt.structuredRequest(
        analysis,
        drill,
        images: images,
        durationSeconds: durationMs / 1000.0,
      );
      final raw = await visionModel!.complete(request);
      final report = AiCoachReport.tryParse(raw);
      if (report == null) {
        debugPrint('AI report rejected: response did not match schema');
      }
      return report;
    } on VisionModelException catch (error) {
      debugPrint('Advanced AI unavailable: ${error.message}');
      return null;
    } on Object catch (error) {
      debugPrint('Advanced AI failed: $error');
      return null;
    }
  }
}
