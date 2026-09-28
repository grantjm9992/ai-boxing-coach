import '../analysis/ai_coach_report.dart';
import '../analysis/ai_review.dart';
import '../analysis/analysis_mode.dart';
import '../analysis/drill.dart';
import '../analysis/round_analysis.dart';
import 'ai/coach_video_model.dart';
import 'ai/coach_vision_model.dart';
import 'ai/coaching_prompt.dart';
import 'ai/video_vision_model.dart';
import 'ai/vision_model.dart';
import 'ai/vision_model_config.dart';
import 'analysis_progress.dart';
import 'frame_grabber.dart';

/// What an AI mode produced, and where it came from (shown by the review
/// screen's SOURCE badge): free-text coaching (key moments), or a structured
/// report whose findings become the round's moments (Full AI review).
class RoundCoaching {
  const RoundCoaching({required this.text, required this.source, this.report});

  final String text;
  final String source;

  /// The Full AI review's structured report; null for free-text coaching.
  final AiCoachReport? report;

  /// [rules] with this coaching applied: a report's confident findings replace
  /// the rules' corrections and moments; free text is attached as coaching.
  RoundAnalysis applyTo(RoundAnalysis rules, {required double durationMs}) {
    final structured = report;
    if (structured == null) return rules.withModelCoaching(text);
    return AiReview.apply(
      rules,
      structured,
      durationSeconds: durationMs > 0 ? durationMs / 1000 : null,
    );
  }
}

/// The AI step of round analysis: given the rules' [RoundAnalysis], ask a model
/// for the coach's read:
///  - [AnalysisMode.keyframe] — a burst of frames around each rule-flagged
///    moment; the model's free-text read is attached, the rules' moments stay;
///  - [AnalysisMode.fullFrame] — the whole round's video at [kFullReviewFps]
///    with the pose measurements, via [videoModel]; the model returns up to
///    seven timestamped findings, which become the round's moments. With no
///    video model (signed out, or AI routed to a custom endpoint) it falls back
///    to the key-moment read, so the user still gets coaching.
///
/// Shared by the background pipeline ([RoundAnalyzer]) and the review screen's
/// re-run, so both treat a mode identically.
class RoundCoach {
  const RoundCoach({this.visionModel, this.frameGrabber, this.videoModel});

  final VisionModel? visionModel;
  final FrameGrabber? frameGrabber;
  final VideoVisionModel? videoModel;

  bool get _canUseFrames => visionModel != null && frameGrabber != null;

  /// Whether [mode] can get any AI coaching with the models configured.
  bool canCoach(AnalysisMode mode) =>
      mode.usesAi &&
      (_canUseFrames || (mode == AnalysisMode.fullFrame && videoModel != null));

  /// The model's coaching, or null when there's nothing to send (no flagged
  /// moments, no decodable frames) or no model for [mode]. Model failures throw
  /// [VisionModelException] — callers decide whether that's silent.
  Future<RoundCoaching?> coach({
    required AnalysisMode mode,
    required String videoPath,
    required RoundAnalysis analysis,
    required DrillContext drill,
    required double durationMs,
    AnalysisProgressCallback? onProgress,
  }) async {
    if (!mode.usesAi) return null;
    if (mode == AnalysisMode.fullFrame && videoModel != null) {
      return _fullVideo(videoPath, analysis, drill, durationMs, onProgress);
    }
    if (_canUseFrames) {
      onProgress?.call(AnalysisStage.reviewing, null);
      return _keyMoments(videoPath, analysis, drill, durationMs);
    }
    return null;
  }

  Future<RoundCoaching?> _fullVideo(
    String videoPath,
    RoundAnalysis analysis,
    DrillContext drill,
    double durationMs,
    AnalysisProgressCallback? onProgress,
  ) async {
    final model = videoModel!;
    final request = CoachingPrompt.fullVideoRequest(
      analysis,
      drill,
      videoPath: videoPath,
      durationSeconds: durationMs > 0 ? durationMs / 1000 : null,
    );
    final progress = onProgress;
    final raw = await model.completeVideo(
      request,
      onProgress: progress == null
          ? null
          : (VideoReviewPhase phase, double? fraction) => progress(
                phase == VideoReviewPhase.uploading
                    ? AnalysisStage.uploading
                    : AnalysisStage.reviewing,
                fraction,
              ),
    );
    // Structured or nothing (brief §18): an unschematic reply is rejected, not
    // shown as prose — the round keeps its rules analysis.
    final parsed = AiCoachReport.tryParse(raw);
    if (parsed == null) {
      throw const VisionModelException(
        'The AI review came back in an unexpected format.',
      );
    }
    final shown = AiReview.shownFindings(
      parsed,
      durationSeconds: durationMs > 0 ? durationMs / 1000 : null,
    ).length;
    return RoundCoaching(
      text: parsed.summary,
      report: parsed,
      source: '${model.label} · full video @ ${request.fps.round()} fps · '
          '$shown of ${parsed.priorityIssues.length} findings shown',
    );
  }

  Future<RoundCoaching?> _keyMoments(
    String videoPath,
    RoundAnalysis analysis,
    DrillContext drill,
    double durationMs,
  ) async {
    // A burst of frames around each flagged moment — motion context, not a
    // single still.
    final bursts = CoachingPrompt.keyframeBursts(analysis, durationMs: durationMs);
    final timestamps = <double>[for (final b in bursts) ...b.timestamps];
    if (timestamps.isEmpty) return null;
    final images = await frameGrabber!.grab(videoPath, timestamps);
    if (images.isEmpty) return null;
    final request = CoachingPrompt.keyframeRequest(analysis, drill, bursts, images);
    final text = (await visionModel!.complete(request)).trim();
    if (text.isEmpty) return null;
    return RoundCoaching(
      text: text,
      source: '${visionModel!.label} · key moments · ${images.length} frames',
    );
  }
}

/// Builds the [RoundCoach] for the user's chosen [mode] and AI settings: no
/// models when the mode is offline; the key-moment model (hosted or the user's
/// own endpoint) for the AI modes; plus the hosted video model for Full AI
/// review. One place, so the session, background and review paths agree.
RoundCoach resolveRoundCoach({
  required AnalysisMode mode,
  required VisionModelConfig config,
}) {
  if (!mode.usesAi) return const RoundCoach();
  final visionModel = resolveCoachVisionModel(config: config);
  return RoundCoach(
    visionModel: visionModel,
    frameGrabber: visionModel != null ? PluginFrameGrabber() : null,
    videoModel: mode == AnalysisMode.fullFrame
        ? resolveCoachVideoModel(config: config)
        : null,
  );
}
