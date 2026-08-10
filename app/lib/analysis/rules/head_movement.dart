import '../context.dart';
import '../geometry.dart' as geo;
import '../landmarks.dart';
import '../round_analysis.dart';
import '../rule.dart';

/// Rule: is there any head movement off the centre line? Mirror of
/// `src/boxing_coach/analysis/rules/head_movement.py`.
///
/// v1 asks only for *presence* of head movement, not quality. We measure lateral
/// spread of the nose relative to the hip-center line, normalised by body scale.
/// A head that never leaves the centre line is easy to hit.
class HeadMovementConfig {
  const HeadMovementConfig({
    this.minLateralStd = 0.06,
    this.minDurationMs = 3000.0,
  });

  /// Std-dev of nose lateral offset (torso-lengths) below which the head is
  /// considered static.
  final double minLateralStd;
  final double minDurationMs;
}

class HeadMovementRule extends Rule {
  HeadMovementRule([HeadMovementConfig? config])
    : _cfg = config ?? const HeadMovementConfig();

  final HeadMovementConfig _cfg;

  @override
  String get id => 'head_movement';

  @override
  Set<String> get focusTags =>
      const <String>{'defence', 'head_movement', 'movement'};

  @override
  List<Observation> evaluate(AnalysisContext context) {
    final cfg = context.styleProfile.configFor(id, _cfg);
    final seq = context.sequence;
    if (seq.durationMs < cfg.minDurationMs) return <Observation>[];

    final scale = context.bodyScale;
    final offsets = <double>[];
    for (final frame in seq.frames) {
      final nose = geo.framePoint(frame, Landmark.nose);
      final center = geo.hipCenter(frame);
      if (nose.any((v) => v.isNaN) || center.any((v) => v.isNaN)) continue;
      offsets.add((nose[0] - center[0]) / scale); // lateral only
    }

    if (offsets.length < 2) return <Observation>[];

    final lateralStd = geo.populationStd(offsets);
    if (lateralStd < cfg.minLateralStd) {
      return <Observation>[
        Observation(
          ruleId: id,
          category: SkillCategory.headMovement,
          severity: Severity.minor,
          coachingText:
              'Your head stayed on the centre line the whole round. Add some '
              "movement — slip off the line so you're not a fixed target.",
          metrics: <String, double>{'lateral_std': lateralStd},
          highlightLandmarks: const <Landmark>[Landmark.nose],
        ),
      ];
    }
    return <Observation>[];
  }
}
