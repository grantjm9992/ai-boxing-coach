import 'dart:math' as math;

import 'features.dart';
import 'geometry.dart' as geo;
import 'landmarks.dart';
import 'pose.dart';

/// Round-level descriptive features — the raw material for national schools.
/// Mirror of `src/boxing_coach/analysis/round_profile.py`.
///
/// The guard [Style] describes defensive *shape*; national schools are tactical
/// *tendencies* that live in these round-level measurements. All are
/// NaN-tolerant and scale-invariant, and descriptive rather than pass/fail.
class RoundProfile {
  const RoundProfile({
    required this.outputPerMin,
    required this.mobility,
    required this.groundCoverage,
    required this.torsoLeanDeg,
    required this.bodyShotRatio,
  });

  final double outputPerMin;
  final double mobility; // torso-lengths/sec of foot travel
  final double groundCoverage; // 0..1, net/gross hip (ankle-centre) displacement
  final double torsoLeanDeg; // angle of the torso off vertical; lower = upright
  final double bodyShotRatio; // 0..1 of punches thrown at body height

  /// Rounded, matching Python's `RoundProfile.as_dict`.
  Map<String, double> asDict() => <String, double>{
    'output_per_min': _round(outputPerMin, 2),
    'mobility': _round(mobility, 3),
    'ground_coverage': _round(groundCoverage, 3),
    'torso_lean_deg': _round(torsoLeanDeg, 1),
    'body_shot_ratio': _round(bodyShotRatio, 3),
  };

  static double _round(double v, int places) {
    final f = math.pow(10, places).toDouble();
    return (v * f).round() / f;
  }
}

RoundProfile computeRoundProfile(
  PoseSequence sequence,
  List<PunchEvent> punches,
  double scale,
) {
  final durationS = sequence.durationMs / 1000.0;
  return RoundProfile(
    outputPerMin: durationS > 0 ? punches.length / durationS * 60.0 : 0.0,
    mobility: _mobility(sequence, scale, durationS),
    groundCoverage: _groundCoverage(sequence),
    torsoLeanDeg: _torsoLeanDeg(sequence),
    bodyShotRatio: _bodyShotRatio(sequence, punches),
  );
}

double _mobility(PoseSequence sequence, double scale, double durationS) {
  if (durationS <= 0) return 0.0;
  final totals = <double>[];
  for (final side in Side.values) {
    var sum = 0.0;
    var any = false;
    List<double>? prev;
    for (final frame in sequence.frames) {
      final p = geo.framePoint(frame, side.ankle);
      if (prev != null && !p.any((v) => v.isNaN) && !prev.any((v) => v.isNaN)) {
        sum += geo.distance(prev, p);
        any = true;
      }
      prev = p;
    }
    if (any) totals.add(sum / scale);
  }
  if (totals.isEmpty) return 0.0;
  final mean = totals.reduce((a, b) => a + b) / totals.length;
  return mean / durationS;
}

double _groundCoverage(PoseSequence sequence) {
  final centres = <List<double>>[
    for (final frame in sequence.frames)
      if (!geo.ankleCenter(frame).any((v) => v.isNaN)) geo.ankleCenter(frame),
  ];
  if (centres.length < 2) return 0.0;
  var total = 0.0;
  for (var i = 1; i < centres.length; i++) {
    total += geo.distance(centres[i - 1], centres[i]);
  }
  if (total == 0) return 0.0;
  final net = geo.distance(centres.first, centres.last);
  return math.min(net / total, 1.0);
}

double _torsoLeanDeg(PoseSequence sequence) {
  // image y grows downward, so "up" is -y.
  final angles = <double>[];
  for (final frame in sequence.frames) {
    final s = geo.shoulderCenter(frame);
    final h = geo.hipCenter(frame);
    final v = <double>[s[0] - h[0], s[1] - h[1]];
    if (v.any((e) => e.isNaN)) continue;
    final norm = math.sqrt(v[0] * v[0] + v[1] * v[1]);
    if (norm == 0) continue;
    // cosine against up = (0,-1): dot = (vx*0 + vy*-1)/norm = -vy/norm
    final cosine = (-v[1] / norm).clamp(-1.0, 1.0);
    angles.add(math.acos(cosine) * 180.0 / math.pi);
  }
  if (angles.isEmpty) return 0.0;
  return angles.reduce((a, b) => a + b) / angles.length;
}

double _bodyShotRatio(PoseSequence sequence, List<PunchEvent> punches) {
  if (punches.isEmpty) return 0.0;
  var body = 0;
  var counted = 0;
  for (final punch in punches) {
    final frame = sequence.frames[punch.peakIndex];
    final wrist = geo.framePoint(frame, punch.side.wrist);
    final shoulder = geo.framePoint(frame, punch.side.shoulder);
    final hip = geo.framePoint(frame, punch.side.hip);
    if (wrist.any((v) => v.isNaN) ||
        shoulder.any((v) => v.isNaN) ||
        hip.any((v) => v.isNaN)) {
      continue;
    }
    counted++;
    final midTorsoY = (shoulder[1] + hip[1]) / 2.0;
    if (wrist[1] > midTorsoY) body++; // y grows downward -> fist below mid-torso
  }
  return counted > 0 ? body / counted : 0.0;
}
