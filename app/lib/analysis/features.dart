import 'geometry.dart' as geo;
import 'pose.dart';

/// Derived features computed once per sequence and shared across rules — the
/// Dart mirror of `src/boxing_coach/analysis/features.py`.
///
/// So far this holds [computeBodyScale]. `PunchDetector` and the punch/reach
/// signals follow as the rules that need them are ported.

/// Median torso length across frames — the person-and-camera-invariant length
/// unit every rule divides by, so thresholds are expressed in "torso-lengths"
/// and hold across people and camera distances rather than pixels.
///
/// Throws if the sequence never yields a usable torso measurement, since every
/// rule's thresholds depend on it.
double computeBodyScale(PoseSequence sequence) {
  final lengths = <double>[
    for (final frame in sequence.frames) geo.torsoLength(frame),
  ];
  final scale = geo.nanMedian(lengths);
  if (!scale.isFinite || scale <= 0) {
    throw StateError(
      'could not establish body scale — no frame had both shoulders and hips '
      'visible',
    );
  }
  return scale;
}
