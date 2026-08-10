import 'landmarks.dart';

/// The structured output of a round analysis — the Dart mirror of
/// `src/boxing_coach/domain/analysis.py`. These are the shapes the coach and the
/// SQLite schema speak in.

/// How much a given observation matters. Ordered worst-first via [rank].
enum Severity {
  positive('positive', 0),
  minor('minor', 1),
  moderate('moderate', 2),
  major('major', 3);

  const Severity(this.value, this.rank);

  final String value;
  final int rank;

  bool get isFault => this != Severity.positive;
}

/// Skill areas from the spec's category tracking. Each observation maps to one.
enum SkillCategory {
  cardio('cardiovascular_endurance'),
  muscularEndurance('muscular_endurance'),
  power('power'),
  footwork('footwork'),
  defence('defence'),
  jab('offence_jab'),
  straight('offence_straight'),
  hooks('offence_hooks'),
  uppercuts('offence_uppercuts'),
  combinations('combinations'),
  headMovement('head_movement'),
  distance('distance_management'),
  rhythm('rhythm_timing');

  const SkillCategory(this.value);

  final String value;
}

/// A single specific thing the analysis noticed, tied to a moment in time.
///
/// [coachingText] is written in coach voice, not technical voice: "you're
/// leaving your hand hanging after the jab", not "wrist-jaw distance exceeded
/// 0.6 body-lengths".
class Observation {
  const Observation({
    required this.ruleId,
    required this.category,
    required this.severity,
    required this.coachingText,
    this.timestampMs,
    this.metrics = const <String, double>{},
    this.highlightLandmarks = const <Landmark>[],
  });

  final String ruleId;
  final SkillCategory category;
  final Severity severity;
  final String coachingText;
  final double? timestampMs;
  final Map<String, double> metrics;

  /// Body parts to emphasise when this moment is shown to the user (e.g. the
  /// wrist that dropped). Drives the skeleton highlight on review.
  final List<Landmark> highlightLandmarks;
}

/// A prioritised, actionable correction distilled from the observations.
class Correction {
  const Correction({
    required this.priority,
    required this.category,
    required this.description,
    this.suggestedDrill,
    this.exampleTimestampMs,
    this.highlightLandmarks = const <Landmark>[],
  });

  final int priority; // 1 = most important
  final SkillCategory category;
  final String description;
  final String? suggestedDrill;
  final double? exampleTimestampMs;
  final List<Landmark> highlightLandmarks;
}

/// A timestamp worth surfacing to the user for frame-by-frame review.
class FlaggedMoment {
  const FlaggedMoment({
    required this.timestampMs,
    required this.reason,
    required this.severity,
  });

  final double timestampMs;
  final String reason;
  final Severity severity;
}

/// Quantitative round summary. Extend freely as rules add signals.
class RoundMetrics {
  const RoundMetrics({
    this.punchesThrown = 0,
    this.guardReturnRate,
    this.punchMix = const <String, int>{},
    this.values = const <String, double>{},
  });

  final int punchesThrown;
  final double? guardReturnRate; // 0..1, null if no punches
  final Map<String, int> punchMix; // named punch -> count
  final Map<String, double> values;
}

/// Everything the analysis produced for one recorded round.
class RoundAnalysis {
  RoundAnalysis({
    required this.overallSummary,
    this.specificObservations = const <Observation>[],
    this.positiveNotes = const <String>[],
    this.correctionPriorities = const <Correction>[],
    this.metrics = const RoundMetrics(),
    this.flaggedMoments = const <FlaggedMoment>[],
  });

  final String overallSummary;
  final List<Observation> specificObservations;
  final List<String> positiveNotes;
  final List<Correction> correctionPriorities;
  final RoundMetrics metrics;
  final List<FlaggedMoment> flaggedMoments;
}
