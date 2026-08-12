import '../context.dart';
import '../round_analysis.dart';
import '../rule.dart';
import '../schools.dart';

/// Rule: is the round being boxed in the chosen national school's game? Mirror
/// of `src/boxing_coach/analysis/rules/school_adherence.py`.
///
/// Only runs when the drill names a [School]. It reads the round-level features
/// and surfaces the school's expectations the round falls short of, in that
/// school's language. Guidance, not a technique fault, so the misses are MINOR —
/// a real fault (a dropped guard) outranks a school nudge.
class SchoolAdherenceRule extends Rule {
  @override
  String get id => 'school_adherence';

  @override
  bool appliesTo(AnalysisContext context) => context.drill.school != null;

  @override
  List<Observation> evaluate(AnalysisContext context) {
    final school = context.drill.school;
    if (school == null) return <Observation>[];

    final profile = schoolProfileFor(school);
    final values = roundFeatureValues(
      context.roundProfile,
      context.punches,
      context.drill.stance,
    );
    final unmet = profile.unmet(values);

    if (unmet.isEmpty) {
      return <Observation>[
        Observation(
          ruleId: id,
          category: profile.expectations.first.category,
          severity: Severity.positive,
          coachingText:
              "Boxing a clean ${profile.label} round — the game's all there.",
        ),
      ];
    }

    return <Observation>[
      for (final exp in unmet)
        Observation(
          ruleId: id,
          category: exp.category,
          severity: Severity.minor,
          coachingText: exp.cue,
        ),
    ];
  }
}
