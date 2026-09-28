/// Provider-agnostic seam for a model that watches a whole video — the
/// "Full AI review" mode. Kept separate from `VisionModel` (images in) because
/// the input is different in kind: one file on disk, sampled by the provider at
/// a frame rate we choose, rather than frames we grab ourselves.

/// Frame rate Full AI review asks the model to sample the round at. Punches are
/// over in a fraction of a second, so anything much lower misses the return to
/// guard. 24 is Gemini's maximum (`0 < fps <= 24`; higher is rejected with
/// FIELD_INVALID). The server clamps to [kGeminiMaxFps] too, and to
/// AI_VIDEO_MAX_FPS as a cost guard.
const double kFullReviewFps = kGeminiMaxFps;

/// The highest `videoMetadata.fps` the Gemini API accepts.
const double kGeminiMaxFps = 24;

/// One request: instructions + prompt + the round's video file.
class VideoVisionRequest {
  const VideoVisionRequest({
    required this.systemPrompt,
    required this.userPrompt,
    required this.videoPath,
    this.fps = kFullReviewFps,
    // Thinking models spend part of this budget reasoning over a long video;
    // headroom so the coaching text itself isn't cut off.
    this.maxTokens = 2048,
    this.temperature = 0.4,
    this.responseSchema,
  });

  final String systemPrompt;
  final String userPrompt;
  final String videoPath;
  final double fps;
  final int maxTokens;
  final double temperature;

  /// When set, the model must answer with JSON matching this schema (Gemini
  /// `responseSchema`, OpenAPI subset); when null it answers in free text.
  final Map<String, Object?>? responseSchema;

  /// The upload mime type, from the file extension (the recorder writes .mp4;
  /// .mov covers imported iOS clips).
  String get mimeType =>
      videoPath.toLowerCase().endsWith('.mov') ? 'video/quicktime' : 'video/mp4';
}

/// A model that turns a [VideoVisionRequest] into coaching text. Throws
/// `VisionModelException` when it can't — the pipeline then keeps the round's
/// offline analysis, exactly as for the image models.
abstract class VideoVisionModel {
  /// Human-readable name of the configured model, for the UI.
  String get label;

  /// Runs [request]. [onProgress] reports the phases the caller can show
  /// while it waits: the upload (with its fraction) and the model's review.
  Future<String> completeVideo(
    VideoVisionRequest request, {
    VideoReviewProgress? onProgress,
  });
}

/// Where a video review is: sending the video, or the model watching it.
enum VideoReviewPhase { uploading, reviewing }

/// Progress callback for [VideoVisionModel.completeVideo]; [fraction] is 0..1
/// while uploading and null once the model is reviewing.
typedef VideoReviewProgress = void Function(
  VideoReviewPhase phase,
  double? fraction,
);

/// Records requests and returns canned text. The test double.
class FakeVideoVisionModel implements VideoVisionModel {
  FakeVideoVisionModel({this.response = 'Full review: keep the rear hand home.'});

  final String response;
  final List<VideoVisionRequest> requests = <VideoVisionRequest>[];

  @override
  String get label => 'Fake video model';

  @override
  Future<String> completeVideo(
    VideoVisionRequest request, {
    VideoReviewProgress? onProgress,
  }) async {
    requests.add(request);
    onProgress?.call(VideoReviewPhase.uploading, 1);
    onProgress?.call(VideoReviewPhase.reviewing, null);
    return response;
  }
}
