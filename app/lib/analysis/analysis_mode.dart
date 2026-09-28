/// How a round is analysed — chosen in the profile, applied to every technical
/// round.
enum AnalysisMode {
  /// Pose + the rule engine on-device, no AI. Free, offline, private. The
  /// default and the whole of v0.5.
  offline('offline', 'Offline', 'On-device pose + rules. Free, offline, private.'),

  /// [offline] first, then an AI model looks at the handful of frames the rules
  /// flagged (plus the pose read as text) and phrases the coaching. Cheap — a
  /// few key frames per round, not the whole clip.
  keyframe(
    'keyframe',
    'Pose + AI on key moments',
    'Rules run on-device; an AI model reviews the flagged moments for '
        'sharper feedback. A few frames per round.',
  ),

  /// [offline] first, then the whole round's video goes to the hosted model
  /// (Gemini, 24 fps — its maximum) with the pose measurements, style, school
  /// and the rules' flags. It returns up to seven timestamped findings, which
  /// become the round's moments. The richest read and the most expensive.
  fullFrame(
    'full_frame',
    'Full AI review',
    'Rules run on-device; an AI model watches the whole round at 24 fps with '
        'your pose data and flags up to 7 moments. Richest feedback, slowest.',
  );

  const AnalysisMode(this.value, this.label, this.blurb);

  final String value;
  final String label;
  final String blurb;

  /// True if the mode calls an AI model at all.
  bool get usesAi => this != AnalysisMode.offline;

  /// Whether this mode can currently be chosen. All are; kept so a mode can be
  /// parked again (shown as "Coming soon") without touching the profile UI.
  bool get available => true;

  static AnalysisMode fromValue(String? value) => AnalysisMode.values.firstWhere(
    (m) => m.value == value,
    orElse: () => AnalysisMode.offline,
  );
}
