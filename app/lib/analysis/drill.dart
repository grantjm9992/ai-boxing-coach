import 'landmarks.dart';

/// A fighting style — selects a [StyleProfile] in the analysis layer. Mirror of
/// `src/boxing_coach/domain/style.py`. "Correct" technique is style-dependent,
/// so judging every style against a textbook high guard gives wrong advice.
enum Style {
  highGuard('high_guard'),
  phillyShell('philly_shell'),
  peekABoo('peek_a_boo'),
  outBoxer('out_boxer');

  const Style(this.value);

  final String value;
}

/// What the round was supposed to be working on — the Dart mirror of
/// `src/boxing_coach/domain/drill.py`. In the app this comes from the session
/// plan (see docs §3.2); it decides which rules are relevant and how feedback is
/// phrased.
class DrillContext {
  const DrillContext({
    this.stance = Stance.orthodox,
    this.style = Style.highGuard,
    this.school,
    this.focus = const <String>{},
    this.notes = '',
  });

  final Stance stance;
  final Style style;

  /// National/tactical school to coach toward. Null = no school feedback (v2).
  final String? school;

  /// Free-form focus tags, e.g. {"jab", "defence"}. Empty = run every rule.
  final Set<String> focus;
  final String notes;

  /// True if this drill targets any of [tags] (or has no focus set).
  bool isFocusedOn(Set<String> tags) =>
      focus.isEmpty || focus.intersection(tags).isNotEmpty;
}
