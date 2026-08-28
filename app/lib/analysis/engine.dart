import 'context.dart';
import 'round_analysis.dart';
import 'rule.dart';
import 'rules/balance.dart';
import 'rules/body_lean.dart';
import 'rules/footwork.dart';
import 'rules/guard_return.dart';
import 'rules/hands_up.dart';
import 'rules/head_movement.dart';
import 'rules/hip_rotation.dart';
import 'rules/school_adherence.dart';

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

/// The full starter rule set — the spec's "Detectable in v1" list. Matches the
/// Python `default_rules()` order (irrelevant to output; the engine sorts).
/// hip_rotation reads z (least certain from a single view); school_adherence
/// runs only when the drill names a School.
List<Rule> defaultRules() => <Rule>[
  ...v05Rules(),
  ...v2Rules(),
];

/// The v0.5 rule set — the Dart↔Python parity contract the golden fixtures were
/// generated against. Frozen: the golden observations tests run exactly these,
/// so their output stays stable as the shipped set grows.
List<Rule> v05Rules() => <Rule>[
  GuardReturnRule(),
  HandsUpRule(),
  FootworkRule(),
  HeadMovementRule(),
  HipRotationRule(),
  SchoolAdherenceRule(),
];

/// V2 analyzers added on top of the v0.5 set (brief §11). Dart-only for now;
/// each carries a confidence reflecting the single-view read (brief §12).
///
/// Scoped deliberately to faults a single frontal view reads honestly: lateral
/// torso lean and lateral hip-over-base balance. Depth-dependent faults
/// (forward/back lean, knee bend / "too upright", body position) are held back
/// until a camera-view signal or side-view support exists rather than inferred
/// unreliably from a frontal projection (brief §12, §35).
List<Rule> v2Rules() => <Rule>[
  BodyLeanRule(),
  BalanceRule(),
];
