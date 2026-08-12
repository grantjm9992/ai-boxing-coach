import 'features.dart';
import 'landmarks.dart';
import 'punch.dart';
import 'round_analysis.dart';
import 'round_profile.dart';
import 'school.dart';

/// School profiles — each national school as expectations on round features.
/// Mirror of `src/boxing_coach/analysis/schools.py`.
///
/// A school is a handful of expectations on the [RoundProfile] plus two punch-
/// selection features (`jab_ratio`, `punch_variety`). The same expectations both
/// classify a round and drive coaching toward a chosen school. Thresholds are
/// starting characterisations to calibrate against real footage, not doctrine.

class Expectation {
  const Expectation({
    required this.feature,
    required this.want, // 'high' (>= threshold) or 'low' (<= threshold)
    required this.threshold,
    required this.cue,
    required this.category,
  });

  final String feature;
  final String want;
  final double threshold;
  final String cue;
  final SkillCategory category;

  bool metBy(double value) =>
      want == 'high' ? value >= threshold : value <= threshold;
}

class SchoolProfile {
  const SchoolProfile({
    required this.school,
    required this.label,
    required this.summary,
    required this.expectations,
  });

  final School school;
  final String label;
  final String summary;
  final List<Expectation> expectations;

  List<Expectation> unmet(Map<String, double> values) => <Expectation>[
    for (final e in expectations)
      if (values.containsKey(e.feature) && !e.metBy(values[e.feature]!)) e,
  ];

  /// Fraction of the measurable expectations the round meets, 0..1.
  double matchScore(Map<String, double> values) {
    final applicable =
        expectations.where((e) => values.containsKey(e.feature)).toList();
    if (applicable.isEmpty) return 0.0;
    final met = applicable.where((e) => e.metBy(values[e.feature]!)).length;
    return met / applicable.length;
  }
}

// Registry order matters: classifySchool breaks score ties by this order,
// matching Python's stable sort over the dict's insertion order.
const List<SchoolProfile> _schoolProfiles = <SchoolProfile>[
  SchoolProfile(
    school: School.mexican,
    label: 'Mexican',
    summary: 'Pressure and volume, built on body work, coming forward.',
    expectations: <Expectation>[
      Expectation(
        feature: 'output_per_min',
        want: 'high',
        threshold: 40.0,
        cue: 'Mexican pressure lives on volume — up the work rate, throw in bunches.',
        category: SkillCategory.rhythm,
      ),
      Expectation(
        feature: 'body_shot_ratio',
        want: 'high',
        threshold: 0.20,
        cue: 'Go downstairs — the Mexican game is built on body work, not just head-hunting.',
        category: SkillCategory.hooks,
      ),
      Expectation(
        feature: 'torso_lean_deg',
        want: 'high',
        threshold: 12.0,
        cue: "Get low and crowd your man — pressure fighters press forward, they don't stand tall.",
        category: SkillCategory.footwork,
      ),
    ],
  ),
  SchoolProfile(
    school: School.soviet,
    label: 'Soviet',
    summary: 'Technical, mobile game behind an educated jab.',
    expectations: <Expectation>[
      Expectation(
        feature: 'mobility',
        want: 'high',
        threshold: 0.30,
        cue: 'Stay on your feet and move — the Soviet system is built on footwork.',
        category: SkillCategory.footwork,
      ),
      Expectation(
        feature: 'jab_ratio',
        want: 'high',
        threshold: 0.40,
        cue: "Lead everything with the jab — it's the spine of the Soviet style.",
        category: SkillCategory.jab,
      ),
    ],
  ),
  SchoolProfile(
    school: School.european,
    label: 'European',
    summary: 'Upright classical stance, long-range jab, points boxing.',
    expectations: <Expectation>[
      Expectation(
        feature: 'torso_lean_deg',
        want: 'low',
        threshold: 10.0,
        cue: 'Stand tall in the classical stance — European boxing is upright and long.',
        category: SkillCategory.footwork,
      ),
      Expectation(
        feature: 'jab_ratio',
        want: 'high',
        threshold: 0.40,
        cue: 'Box behind a long jab and hold your range.',
        category: SkillCategory.jab,
      ),
      Expectation(
        feature: 'body_shot_ratio',
        want: 'low',
        threshold: 0.15,
        cue: 'Keep it upstairs at range — this is a points game, not a body war.',
        category: SkillCategory.distance,
      ),
    ],
  ),
  SchoolProfile(
    school: School.american,
    label: 'American',
    summary: 'Athletic, varied power combinations rather than a jab-led game.',
    expectations: <Expectation>[
      Expectation(
        feature: 'output_per_min',
        want: 'high',
        threshold: 40.0,
        cue: 'American boxing is busy — let your hands go in combination.',
        category: SkillCategory.combinations,
      ),
      Expectation(
        feature: 'punch_variety',
        want: 'high',
        threshold: 3.0,
        cue: 'Mix your punches — jab, cross, hook, uppercut — not one note.',
        category: SkillCategory.combinations,
      ),
      Expectation(
        feature: 'jab_ratio',
        want: 'low',
        threshold: 0.45,
        cue: "Don't just pump the jab — American boxing turns over power combinations.",
        category: SkillCategory.combinations,
      ),
    ],
  ),
];

SchoolProfile schoolProfileFor(School school) =>
    _schoolProfiles.firstWhere((p) => p.school == school);

/// Ranks schools by how well the round's features match each, best first.
/// Stable on ties (registry order), matching the Python reference.
List<(School, double)> classifySchool(Map<String, double> values) {
  final scored = <(int, School, double)>[
    for (var i = 0; i < _schoolProfiles.length; i++)
      (i, _schoolProfiles[i].school, _schoolProfiles[i].matchScore(values)),
  ]..sort((a, b) {
    final byScore = b.$3.compareTo(a.$3);
    return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
  });
  return <(School, double)>[for (final s in scored) (s.$2, s.$3)];
}

/// The feature dict schools are judged on: round profile + punch selection.
Map<String, double> roundFeatureValues(
  RoundProfile profile,
  List<PunchEvent> punches,
  Stance stance,
) {
  final total = punches.length;
  final jabs = punches
      .where((p) => p.punchType == PunchType.straight && p.side == stance.lead)
      .length;
  final variety = total > 0
      ? punches
            .map((p) => punchName(p.punchType, p.side, stance))
            .toSet()
            .length
      : 0;
  return <String, double>{
    'output_per_min': profile.outputPerMin,
    'mobility': profile.mobility,
    'ground_coverage': profile.groundCoverage,
    'torso_lean_deg': profile.torsoLeanDeg,
    'body_shot_ratio': profile.bodyShotRatio,
    'jab_ratio': total > 0 ? jabs / total : 0.0,
    'punch_variety': variety.toDouble(),
  };
}
