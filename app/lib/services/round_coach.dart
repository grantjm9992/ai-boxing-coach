import '../analysis/analysis_mode.dart';
import '../analysis/drill.dart';
import '../analysis/round_analysis.dart';
import 'ai/coach_video_model.dart';
import 'ai/coach_vision_model.dart';
import 'ai/coaching_prompt.dart';
import 'ai/video_vision_model.dart';
import 'ai/vision_model.dart';
import 'ai/vision_model_config.dart';
import 'frame_grabber.dart';

/// The coaching text an AI mode produced, and where it came from (shown by the
/// review screen's SOURCE badge).
class RoundCoaching {
  const RoundCoaching({required this.text, required this.source});

  final String text;
  final String source;
}

/// The AI step of round analysis: given the rules' [RoundAnalysis], ask a model
/// for the coach's read. The rules' flagged moments are what the review screen
/// highlights in every mode — this only decides what the model is shown:
///  - [AnalysisMode.keyframe] — a burst of frames around each flagged moment;
///  - [AnalysisMode.fullFrame] — the whole round's video at
///    [kFullReviewFps], via [videoModel]. With no video model (signed out, or
///    AI routed to a custom endpoint) it falls back to the key-moment read, so
///    the user still gets coaching.
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
  }) async {
    if (!mode.usesAi) return null;
    if (mode == AnalysisMode.fullFrame && videoModel != null) {
      return _fullVideo(videoPath, analysis, drill);
    }
    if (_canUseFrames) {
      return _keyMoments(videoPath, analysis, drill, durationMs);
    }
    return null;
  }

  Future<RoundCoaching?> _fullVideo(
    String videoPath,
    RoundAnalysis analysis,
    DrillContext drill,
  ) async {
    final model = videoModel!;
    final request = CoachingPrompt.fullVideoRequest(
      analysis,
      drill,
      videoPath: videoPath,
    );
    final text = (await model.completeVideo(request)).trim();
    if (text.isEmpty) return null;
    return RoundCoaching(
      text: text,
      source: '${model.label} · full video @ ${request.fps.round()} fps',
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
