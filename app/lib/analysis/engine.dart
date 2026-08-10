import 'context.dart';
import 'round_analysis.dart';
import 'rule.dart';
import 'rules/footwork.dart';
import 'rules/guard_return.dart';
import 'rules/hands_up.dart';
import 'rules/head_movement.dart';

/// RuleEngine — runs the rule set over one round and collects observations.
/// Mirror of `src/boxing_coach/analysis/engine.py`.
///
/// Deliberately dumb: decides which rules apply, runs each, gathers the results,
/// and isolates a single failing rule so one bad rule can't sink the analysis.
class RuleEngine {
  RuleEngine(List<Rule> rules) : _rules = List<Rule>.of(rules);

  final List<Rule> _rules;

  List<Rule> get rules => List<Rule>.of(_rules);

  List<Observation> run(AnalysisContext context) {
    final observations = <Observation>[];
    for (final rule in _rules) {
      if (!context.styleProfile.enables(rule.id)) continue;
      if (!rule.appliesTo(context)) continue;
      try {
        observations.addAll(rule.evaluate(context));
      } on Object {
        // One rule failing must not sink the round.
      }
    }

    // Worst faults first, positives last — stable on ties so the order rules ran
    // in is preserved (matching Python's stable sort). Dart's sort is not stable,
    // so we break ties on the original index explicitly.
    final indexed = <(int, Observation)>[
      for (var i = 0; i < observations.length; i++) (i, observations[i]),
    ]..sort((a, b) {
      final byRank = b.$2.severity.rank.compareTo(a.$2.severity.rank);
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
    return <Observation>[for (final entry in indexed) entry.$2];
  }
}

/// The v0.5 starter rule set — the spec's "Detectable in v1" list minus the two
/// v2 rules (hip_rotation needs z; school_adherence needs a coach's input).
/// Order is irrelevant; the engine sorts the output.
List<Rule> defaultRules() => <Rule>[
  GuardReturnRule(),
  HandsUpRule(),
  FootworkRule(),
  HeadMovementRule(),
];
