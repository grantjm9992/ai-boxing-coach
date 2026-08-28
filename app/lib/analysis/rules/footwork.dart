import '../context.dart';
import '../error_codes.dart';
import '../geometry.dart' as geo;
import '../landmarks.dart';
import '../round_analysis.dart';
import '../rule.dart';

/// Rule: is the boxer moving, or rooted to the spot? Mirror of
/// `src/boxing_coach/analysis/rules/footwork.py`.
///
/// Cheap and reliable from pose alone: total ankle travel across the round,
/// normalised by body scale and time. Near-zero movement means a stationary
/// target.
class FootworkConfig {
  const FootworkConfig({
    this.minTravelPerSecond = 0.15,
    this.minDurationMs = 3000.0,
  });

  /// Minimum mean ankle travel (torso-lengths per second) to count as "moving".
  final double minTravelPerSecond;
  final double minDurationMs;
}

class FootworkRule extends Rule {
  FootworkRule([FootworkConfig? config]) : _cfg = config ?? const FootworkConfig();

  final FootworkConfig _cfg;

  @override
  String get id => 'footwork';

  @override
  Set<String> get focusTags =>
      const <String>{'footwork', 'movement', 'defence'};

  @override
  List<Observation> evaluate(AnalysisContext context) {
    final cfg = context.styleProfile.configFor(id, _cfg);
    final seq = context.sequence;
    final durationS = seq.durationMs / 1000.0;
    if (seq.durationMs < cfg.minDurationMs || durationS <= 0) {
      return <Observation>[];
    }

    final travel = _meanAnkleTravelPerSecond(context, durationS);
    if (travel == null) return <Observation>[];

    if (travel < cfg.minTravelPerSecond) {
      return <Observation>[
        Observation(
          ruleId: id,
          code: FaultCode.footFlatFooted,
          category: SkillCategory.footwork,
          severity: Severity.moderate,
          coachingText:
              "You're flat-footed this round — barely moving. Stay light, step "
              'in and out, work angles instead of standing square.',
          metrics: <String, double>{'travel_per_second': travel},
          highlightLandmarks: <Landmark>[Side.left.ankle, Side.right.ankle],
        ),
      ];
    }
    return <Observation>[
      Observation(
        ruleId: id,
        category: SkillCategory.footwork,
        severity: Severity.positive,
        coachingText:
            "Good movement — you're staying light on your feet, not rooted.",
        metrics: <String, double>{'travel_per_second': travel},
      ),
    ];
  }

  /// Mean of the two ankles' total path length per second (torso-lengths).
  /// Only adjacent frames where the ankle is present in both contribute — a gap
  /// contributes nothing, matching numpy's `diff` + NaN drop.
  double? _meanAnkleTravelPerSecond(AnalysisContext context, double durationS) {
    final seq = context.sequence;
    final scale = context.bodyScale;
    final totals = <double>[];
    for (final side in Side.values) {
      var sum = 0.0;
      var any = false;
      List<double>? prev;
      for (final frame in seq.frames) {
        final p = geo.framePoint(frame, side.ankle);
        if (prev != null && !p.any((v) => v.isNaN) && !prev.any((v) => v.isNaN)) {
          sum += geo.distance(prev, p);
          any = true;
        }
        prev = p;
      }
      if (any) totals.add(sum / scale);
    }
    if (totals.isEmpty) return null;
    final mean = totals.reduce((a, b) => a + b) / totals.length;
    return mean / durationS;
  }
}
