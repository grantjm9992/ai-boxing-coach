import 'package:flutter/foundation.dart';

import '../analysis/drill.dart';
import '../analysis/pose_only_adapter.dart';
import '../analysis/round_analysis.dart';
import '../domain/round_clip.dart';
import 'analysis_store.dart';
import 'pose_estimator.dart';

/// Runs the full analysis pipeline over a recorded round: pose estimation ->
/// rule engine + PoseOnlyAdapter -> a [RoundAnalysis], persisted for review and
/// history.
///
/// Returns null (rather than throwing) when analysis can't run — no camera, no
/// model, decode failure — because coaching is additive: a round with no
/// analysis is exactly the v0.1 experience, never a broken session.
class RoundAnalyzer {
  RoundAnalyzer({
    PoseEstimator? estimator,
    AnalysisStore? store,
    PoseOnlyAdapter? adapter,
  }) : _estimator = estimator ?? MediaPipePoseEstimator(),
       _store = store ?? AnalysisStore(),
       _adapter = adapter ?? PoseOnlyAdapter();

  final PoseEstimator _estimator;
  final AnalysisStore _store;
  final PoseOnlyAdapter _adapter;

  Future<RoundAnalysis?> analyse(RoundClip clip, {DrillContext? drill}) async {
    try {
      PoseAnalysisResult? result;
      await for (final progress in _estimator.analyse(clip.path)) {
        if (progress.result != null) result = progress.result;
      }
      if (result == null) return null;

      final analysis = _adapter.analyse(
        result.sequence,
        drill ?? const DrillContext(),
      );
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
}
