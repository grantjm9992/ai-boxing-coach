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

  /// A vision model watches sampled frames across the whole round (~2–5 fps).
  /// The richest and the most expensive; needs a configured endpoint.
  fullFrame(
    'full_frame',
    'Full AI review',
    'A vision model watches the whole round (sampled). Richest feedback, '
        'highest cost — needs a model endpoint.',
  );

  const AnalysisMode(this.value, this.label, this.blurb);

  final String value;
  final String label;
  final String blurb;

  /// True if the mode calls an AI model at all.
  bool get usesAi => this != AnalysisMode.offline;

  static AnalysisMode fromValue(String? value) => AnalysisMode.values.firstWhere(
    (m) => m.value == value,
    orElse: () => AnalysisMode.offline,
  );
}
