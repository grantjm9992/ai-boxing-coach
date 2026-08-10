import 'context.dart';
import 'round_analysis.dart';

/// The `Rule` seam — mirror of `src/boxing_coach/analysis/rule.py`.
///
/// A single technique check over a round's pose sequence. Adding a rule is one
/// subclass; the engine discovers nothing implicitly. Each rule declares which
/// drill focus tags it is relevant to so the engine can skip irrelevant rules.
abstract class Rule {
  /// Stable identifier, e.g. "guard_return". Appears on every [Observation].
  String get id;

  /// Drill focus tags this rule is relevant to. Empty = always run; otherwise
  /// it runs only when the drill targets one of them.
  Set<String> get focusTags => const <String>{};

  bool appliesTo(AnalysisContext context) =>
      focusTags.isEmpty || context.drill.isFocusedOn(focusTags);

  /// Zero or more observations. Empty means nothing to report.
  List<Observation> evaluate(AnalysisContext context);
}
