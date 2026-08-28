/// The analysis *intent* of one recorded round — what it is, and therefore
/// which expectations and thresholds the analyzers should apply.
///
/// This is a different axis from `SessionPhase` (domain/session_phase.dart),
/// which describes position within a guided session arc. A round always has a
/// [SessionType]: standalone recordings set it directly; rounds inside a guided
/// session derive it from their phase (see `SessionPhase.sessionType`).
///
/// V2 brief §4. Values are the wire form and match the brief's enum.
enum SessionType {
  /// Full shadow-boxing round, no bag. Full body should stay visible; footwork,
  /// balance and body position all in scope.
  shadowBoxing('SHADOW_BOXING', 'Shadow boxing'),

  /// Work on a bag. Impact frames are present; distance/footwork expectations
  /// differ from shadow.
  heavyBag('HEAVY_BAG', 'Heavy bag'),

  /// Deliberate work on one technique or combination rather than a free round.
  technicalWork('TECHNICAL_WORK', 'Technical work'),

  /// A guided combination drill with a known target sequence.
  combinationDrill('COMBINATION_DRILL', 'Combination drill'),

  /// Anything not otherwise specified. The neutral default.
  freeTraining('FREE_TRAINING', 'Free training');

  const SessionType(this.value, this.label);

  /// The wire value, matching the brief's enum names.
  final String value;

  /// Human-readable name for the UI.
  final String label;

  static SessionType fromValue(String? value) => SessionType.values.firstWhere(
    (t) => t.value == value,
    orElse: () => SessionType.freeTraining,
  );
}
