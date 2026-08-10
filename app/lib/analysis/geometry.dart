import 'dart:math' as math;

import 'landmarks.dart';
import 'pose.dart';

/// Tiny geometry helpers — the Dart mirror of
/// `src/boxing_coach/analysis/geometry.py`.
///
/// NaN-tolerant where it matters: pose estimation drops landmarks, and it is
/// better to propagate NaN than to crash or fabricate a position. Points are
/// `List<double>` of length 2 (v0.5 works entirely in the image plane; z is
/// treated as unusable, per the design note).

const List<double> _nan2 = <double>[double.nan, double.nan];

List<double> midpoint(List<double> a, List<double> b) =>
    <double>[(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0];

double distance(List<double> a, List<double> b) {
  final dx = a[0] - b[0];
  final dy = a[1] - b[1];
  return math.sqrt(dx * dx + dy * dy);
}

/// The 2D position of [landmark] in [frame], or [NaN, NaN] if it is missing.
List<double> framePoint(PoseFrame frame, Landmark landmark) {
  final kp = frame.get(landmark);
  return kp == null ? _nan2 : kp.xy;
}

List<double> shoulderCenter(PoseFrame frame) => midpoint(
  framePoint(frame, Landmark.leftShoulder),
  framePoint(frame, Landmark.rightShoulder),
);

List<double> hipCenter(PoseFrame frame) => midpoint(
  framePoint(frame, Landmark.leftHip),
  framePoint(frame, Landmark.rightHip),
);

List<double> ankleCenter(PoseFrame frame) => midpoint(
  framePoint(frame, Landmark.leftAnkle),
  framePoint(frame, Landmark.rightAnkle),
);

/// Distance from shoulder-center to hip-center (2D). The scale unit. More
/// stable than shoulder width, which foreshortens as the boxer turns.
double torsoLength(PoseFrame frame) =>
    distance(shoulderCenter(frame), hipCenter(frame));

/// Angle at vertex [b] formed by a-b-c, in degrees (NaN if undetermined). Used
/// for joint angles like the elbow: ~180° straight, ~90° bent.
double angleDeg(List<double> a, List<double> b, List<double> c) {
  final ba = <double>[a[0] - b[0], a[1] - b[1]];
  final bc = <double>[c[0] - b[0], c[1] - b[1]];
  if (_hasNan(ba) || _hasNan(bc)) return double.nan;
  final denom = _norm(ba) * _norm(bc);
  if (denom == 0) return double.nan;
  final cosine = (ba[0] * bc[0] + ba[1] * bc[1]) / denom;
  final clamped = cosine.clamp(-1.0, 1.0);
  return math.acos(clamped) * 180.0 / math.pi;
}

/// Median of the finite values, ignoring NaN — matching `numpy.nanmedian`
/// (linear interpolation, so an even count averages the two middle values).
/// Returns NaN when there is nothing finite to take a median of.
double nanMedian(List<double> values) {
  final finite = <double>[
    for (final v in values)
      if (v.isFinite) v,
  ]..sort();
  final n = finite.length;
  if (n == 0) return double.nan;
  final mid = n ~/ 2;
  if (n.isOdd) return finite[mid];
  return (finite[mid - 1] + finite[mid]) / 2.0;
}

/// The [q]-th percentile (0..100) of the finite values, ignoring NaN — matching
/// `numpy.nanpercentile` with its default linear interpolation.
double nanPercentile(List<double> values, double q) {
  final finite = <double>[
    for (final v in values)
      if (v.isFinite) v,
  ]..sort();
  final n = finite.length;
  if (n == 0) return double.nan;
  if (n == 1) return finite.first;
  final rank = (q / 100.0) * (n - 1);
  final lower = rank.floor();
  final upper = rank.ceil();
  if (lower == upper) return finite[lower];
  final frac = rank - lower;
  return finite[lower] + frac * (finite[upper] - finite[lower]);
}

/// Index of the maximum finite value, ignoring NaN — matching `numpy.nanargmax`
/// (first occurrence on ties). Returns 0 if nothing is finite.
int nanArgmax(List<double> values) {
  var bestIndex = 0;
  var best = double.negativeInfinity;
  var seen = false;
  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    if (v.isNaN) continue;
    if (!seen || v > best) {
      best = v;
      bestIndex = i;
      seen = true;
    }
  }
  return bestIndex;
}

bool _hasNan(List<double> v) => v.any((e) => e.isNaN);

double _norm(List<double> v) => math.sqrt(v[0] * v[0] + v[1] * v[1]);
