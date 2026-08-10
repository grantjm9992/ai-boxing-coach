import 'drill.dart';

/// StyleProfile — how a fighting [Style] tunes and gates the rule set for one
/// round. Mirror of `src/boxing_coach/analysis/style.py`.
///
/// It gates rules (a rule that would give wrong advice for a style is switched
/// off) and overrides rule configs (thresholds that legitimately differ by
/// style). v0.5 ships only the neutral [defaultStyleProfile]; the per-style
/// registry is v2, gated on a real coach's input.
class StyleProfile {
  const StyleProfile({
    required this.style,
    required this.label,
    required this.summary,
    this.disabledRules = const <String>{},
    this.ruleConfigs = const <String, Object>{},
  });

  final Style style;
  final String label;
  final String summary;

  /// Rule ids switched off entirely for this style.
  final Set<String> disabledRules;

  /// rule_id -> replacement config. Missing = the rule's own default.
  final Map<String, Object> ruleConfigs;

  bool enables(String ruleId) => !disabledRules.contains(ruleId);

  /// The style's config override for [ruleId], or [fallback] if none.
  T configFor<T>(String ruleId, T fallback) {
    final override = ruleConfigs[ruleId];
    return override is T ? override : fallback;
  }
}

/// The neutral profile: every rule on, every threshold at its own default.
const StyleProfile defaultStyleProfile = StyleProfile(
  style: Style.highGuard,
  label: 'High guard (textbook)',
  summary: 'Standard hands-up guard. Every rule runs at its default thresholds.',
);
