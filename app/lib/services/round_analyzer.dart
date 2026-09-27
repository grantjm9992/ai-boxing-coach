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
import 'ai/video_vision_model.dart';
import 'ai/vision_model.dart';
import 'analysis_store.dart';
import 'frame_grabber.dart';
import 'pose_estimator.dart';
import 'round_coach.dart';

/// Runs the analysis pipeline over a recorded round and persists the result.
///
/// Always runs pose + the rule engine on-device (that gives the metrics, the
/// review skeleton, the flagged moments and the base coaching, for free). In
/// the AI modes it then layers a model's read on top via [RoundCoach]:
///  - [AnalysisMode.keyframe] sends the handful of frames the rules flagged;
///  - [AnalysisMode.fullFrame] sends the whole round's video.
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
    this.videoModel,
  }) : _estimator = estimator ?? MediaPipePoseEstimator(),
       _store = store ?? AnalysisStore(),
       _adapter = adapter ?? PoseOnlyAdapter(),
       _analytics = analytics ?? AnalyticsScope.instance;

  /// An analyzer whose AI step uses [coach]'s models (see [resolveRoundCoach]).
  factory RoundAnalyzer.withCoach(RoundCoach coach) => RoundAnalyzer(
    visionModel: coach.visionModel,
    frameGrabber: coach.frameGrabber,
    videoModel: coach.videoModel,
  );

  final PoseEstimator _estimator;
  final AnalysisStore _store;
  final PoseOnlyAdapter _adapter;
  final Analytics _analytics;
  final VisionModel? visionModel;
  final FrameGrabber? frameGrabber;
  final VideoVisionModel? videoModel;

  late final RoundCoach _coach = RoundCoach(
    visionModel: visionModel,
    frameGrabber: frameGrabber,
    videoModel: videoModel,
  );

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

      if (FeatureFlags.advancedAiAnalysis &&
          mode == AnalysisMode.fullFrame &&
          visionModel != null &&
          frameGrabber != null) {
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
      } else if (_coach.canCoach(mode)) {
        final coaching = await _aiCoaching(
          mode,
          clip,
          analysis,
          resolvedDrill,
          result.sequence.durationMs,
        );
        if (coaching != null) {
          analysis = analysis.withModelCoaching(coaching.text);
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

  Future<RoundCoaching?> _aiCoaching(
    AnalysisMode mode,
    RoundClip clip,
    RoundAnalysis analysis,
    DrillContext drill,
    double durationMs,
  ) async {
    try {
      return await _coach.coach(
        mode: mode,
        videoPath: clip.path,
        analysis: analysis,
        drill: drill,
        durationMs: durationMs,
      );
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
