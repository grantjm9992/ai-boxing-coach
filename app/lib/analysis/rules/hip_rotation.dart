import '../context.dart';
import '../error_codes.dart';
import '../geometry.dart' as geo;
import '../landmarks.dart';
import '../punch.dart';
import '../round_analysis.dart';
import '../rule.dart';

/// Rule: is the rear hand punched with rotation, or arm-only? Mirror of
/// `src/boxing_coach/analysis/rules/hip_rotation.py`.
///
/// A cross should be driven by hip/shoulder rotation — the rear shoulder comes
/// forward. We take the larger of the in-plane swing (x/y, a side camera) and
/// the depth drive (z, a front camera), relative to the hip centre so a step
/// isn't mistaken for rotation. Least certain of the rules: z is only estimated.
class HipRotationConfig {
  const HipRotationConfig({
    this.minShoulderDrive = 0.12,
    this.minPeakReach = 0.9,
  });

  final double minShoulderDrive;
  final double minPeakReach;
}

class HipRotationRule extends Rule {
  HipRotationRule([HipRotationConfig? config])
    : _cfg = config ?? const HipRotationConfig();

  final HipRotationConfig _cfg;

  @override
  String get id => 'hip_rotation';

  @override
  Set<String> get focusTags =>
      const <String>{'straight', 'power', 'combinations'};

  @override
  List<Observation> evaluate(AnalysisContext context) {
    final cfg = context.styleProfile.configFor(id, _cfg);
    final rear = context.drill.stance.rear;
    final seq = context.sequence;
    final observations = <Observation>[];

    for (final punch in context.punchesBy(rear)) {
      // Only the rear straight is driven by rotation this way.
      if (punch.punchType != PunchType.straight) continue;
      if (punch.peakReach < cfg.minPeakReach) continue;
      final drive = geo.shoulderDrive(
        seq,
        rear,
        punch.startIndex,
        punch.peakIndex,
        context.bodyScale,
      );
      if (drive == null) continue;
      if (drive < cfg.minShoulderDrive) {
        observations.add(
          Observation(
            ruleId: id,
            code: FaultCode.rotInsufficient,
            category: SkillCategory.straight,
            severity: Severity.moderate,
            coachingText:
                "You're squared up on the rear straight — punching with the arm. "
                'Turn the hip and shoulder over; let the rotation drive the shot.',
            timestampMs: punch.peakTimestampMs(seq),
            metrics: <String, double>{'shoulder_drive': drive},
            highlightLandmarks: <Landmark>[rear.shoulder],
          ),
        );
      }
    }
    return observations;
  }
}
