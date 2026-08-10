import 'geometry.dart' as geo;
import 'landmarks.dart';
import 'pose.dart';
import 'punch.dart';

/// Classify a detected punch into a motion class — mirror of
/// `src/boxing_coach/analysis/punch_classifier.py`.
///
/// Works from the wrist's start→peak path plus the elbow angle at the peak when
/// the elbow landmark is available (a reach-based fallback otherwise). All
/// lengths are in torso-lengths. Single-view 2D separates these unevenly, so the
/// type is a useful signal, not ground truth.
class PunchClassifierConfig {
  const PunchClassifierConfig({
    this.uppercutMinRise = 0.55,
    this.hookMinHoriz = 0.45,
    this.extendedElbowDeg = 150.0,
    this.extendedReach = 1.2,
  });

  final double uppercutMinRise;
  final double hookMinHoriz;
  final double extendedElbowDeg;
  final double extendedReach;
}

PunchType classifyPunch(
  PoseSequence sequence,
  Side side,
  int startIndex,
  int peakIndex,
  double peakReach,
  double scale, {
  PunchClassifierConfig config = const PunchClassifierConfig(),
}) {
  final start = sequence.frames[startIndex];
  final peak = sequence.frames[peakIndex];

  final w0 = geo.framePoint(start, side.wrist);
  final w1 = geo.framePoint(peak, side.wrist);
  if (w0.any((v) => v.isNaN) || w1.any((v) => v.isNaN)) {
    return PunchType.unknown;
  }

  final dx = (w1[0] - w0[0]) / scale;
  final dy = (w1[1] - w0[1]) / scale;
  final rise = -dy; // y grows downward, so upward travel is positive rise
  final horiz = dx.abs();

  // Is the arm extended at the peak? Elbow angle if we have it, else reach.
  final elbowAngle = geo.angleDeg(
    geo.framePoint(peak, side.shoulder),
    geo.framePoint(peak, side.elbow),
    geo.framePoint(peak, side.wrist),
  );
  final bool extended;
  if (!elbowAngle.isNaN) {
    extended = elbowAngle >= config.extendedElbowDeg;
  } else {
    extended = peakReach >= config.extendedReach;
  }

  if (rise >= config.uppercutMinRise && rise >= horiz) {
    return PunchType.uppercut;
  }
  if (extended) return PunchType.straight;
  if (horiz >= config.hookMinHoriz) return PunchType.hook;
  return PunchType.unknown;
}
