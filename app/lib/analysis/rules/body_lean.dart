import 'dart:math' as math;

import '../context.dart';
import '../error_codes.dart';
import '../geometry.dart' as geo;
import '../landmarks.dart';
import '../round_analysis.dart';
import '../rule.dart';

/// Rule: is the torso held off-vertical through the round? (Brief §11.1.)
///
/// Measures the hip-centre→shoulder-centre vector's tilt away from vertical in
/// the image plane. Lateral (left/right) lean is what a single 2D view reads
/// reliably; forward/backward lean is depth and is *not* inferred here — that
/// would need a side view, so this rule stays in-plane and carries a confidence
/// reflecting the 2D read (brief §12).
///
/// A boxer whose torso is consistently tilted off-centre is off-balance and
/// telegraphs weight; a small amount of tilt is normal, so we threshold on the
/// robust median tilt across the round, not a single frame.
class BodyLeanConfig {
  const BodyLeanConfig({
    this.maxTiltDeg = 12.0,
    this.moderateTiltDeg = 20.0,
    this.minDurationMs = 3000.0,
    this.confidence = 0.8,
  });

  /// Median torso tilt from vertical (degrees) above which lean is flagged.
  final double maxTiltDeg;

  /// Tilt above which the fault is moderate rather than minor.
  final double moderateTiltDeg;

  final double minDurationMs;

  /// How much to trust an in-plane 2D tilt read (brief §12).
  final double confidence;
}

class BodyLeanRule extends Rule {
  BodyLeanRule([BodyLeanConfig? config])
    : _cfg = config ?? const BodyLeanConfig();

  final BodyLeanConfig _cfg;

  @override
  String get id => 'body_lean';

  @override
  Set<String> get focusTags =>
      const <String>{'defence', 'movement', 'balance', 'posture'};

  @override
  List<Observation> evaluate(AnalysisContext context) {
    final cfg = context.styleProfile.configFor(id, _cfg);
    final seq = context.sequence;
    if (seq.durationMs < cfg.minDurationMs) return <Observation>[];

    // Signed tilt per frame: + = torso leans toward image-right, - = image-left.
    final tilts = <double>[];
    for (final frame in seq.frames) {
      final shoulders = geo.shoulderCenter(frame);
      final hips = geo.hipCenter(frame);
      if (shoulders.any((v) => v.isNaN) || hips.any((v) => v.isNaN)) continue;
      final dx = shoulders[0] - hips[0];
      final dy = shoulders[1] - hips[1]; // up is negative y
      // Angle of the torso vector from the vertical (up) axis.
      final tiltDeg = math.atan2(dx, -dy) * 180.0 / math.pi;
      if (tiltDeg.isNaN) continue;
      tilts.add(tiltDeg);
    }
    if (tilts.length < 2) return <Observation>[];

    final median = geo.nanMedian(tilts);
    final magnitude = median.abs();
    if (magnitude < cfg.maxTiltDeg) return <Observation>[];

    final leansRight = median > 0;
    return <Observation>[
      Observation(
        ruleId: id,
        code: leansRight ? FaultCode.leanRight : FaultCode.leanLeft,
        category: SkillCategory.defence,
        severity:
            magnitude >= cfg.moderateTiltDeg ? Severity.moderate : Severity.minor,
        confidence: cfg.confidence,
        coachingText:
            'Your torso is leaning off-centre most of the round. Stack your '
            'shoulders over your hips — a tilted upper body costs you balance '
            'and power.',
        metrics: <String, double>{'median_tilt_deg': median},
        highlightLandmarks: const <Landmark>[
          Landmark.leftShoulder,
          Landmark.rightShoulder,
        ],
      ),
    ];
  }
}
