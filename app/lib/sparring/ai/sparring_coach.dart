import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/ai/coach_video_model.dart';
import '../../services/ai/video_vision_model.dart';
import '../../services/ai/vision_model.dart';
import '../../services/supabase/supabase_config.dart';
import '../analysis/sparring_analyzer.dart';
import 'sparring_report.dart';
import 'sparring_review.dart';

/// Runs the AI coach's review of a sparring round through the `sparring` edge
/// function (its own function — the `analyze` one is untouched — drawing on the
/// same weekly AI allowance). The client is the existing [CoachVideoModel],
/// pointed at that function: same upload-then-generate protocol.
class SparringCoach {
  SparringCoach({required this.model});

  final VideoVisionModel model;

  static String get endpointBaseUrl => '${SupabaseConfig.url}/functions/v1/sparring';

  /// The hosted model when signed in; null otherwise (the round keeps its
  /// on-device analysis).
  static SparringCoach? resolve() {
    try {
      if (Supabase.instance.client.auth.currentSession != null) {
        return SparringCoach(model: CoachVideoModel(endpointBaseUrl: endpointBaseUrl));
      }
    } on Object {
      // Supabase not initialised (tests).
    }
    return null;
  }

  /// Sends [request] and folds the report into [analysis]. Throws
  /// [VisionModelException] when the model fails or its answer doesn't parse.
  Future<SparringRoundAnalysis> review(
    VideoVisionRequest request,
    SparringRoundAnalysis analysis, {
    VideoReviewProgress? onProgress,
  }) async {
    final text = await model.completeVideo(request, onProgress: onProgress);
    final report = SparringAiReport.tryParse(text);
    if (report == null) {
      throw const VisionModelException("The AI coach's answer couldn't be read.");
    }
    return SparringReview.apply(analysis, report);
  }
}
