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

  static Severity fromValue(String value) =>
      Severity.values.firstWhere((s) => s.value == value,
          orElse: () => Severity.minor);
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

  static SkillCategory fromValue(String value) =>
      SkillCategory.values.firstWhere((c) => c.value == value,
          orElse: () => SkillCategory.defence);
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

  Map<String, Object?> toJson() => <String, Object?>{
    'ruleId': ruleId,
    'category': category.value,
    'severity': severity.value,
    'coachingText': coachingText,
    'timestampMs': timestampMs,
    'metrics': metrics,
    'highlight': highlightLandmarks.map((l) => l.mpIndex).toList(),
  };

  factory Observation.fromJson(Map<String, Object?> json) => Observation(
    ruleId: json['ruleId'] as String,
    category: SkillCategory.fromValue(json['category'] as String),
    severity: Severity.fromValue(json['severity'] as String),
    coachingText: json['coachingText'] as String,
    timestampMs: (json['timestampMs'] as num?)?.toDouble(),
    metrics: <String, double>{
      for (final e in (json['metrics'] as Map<String, Object?>? ?? const {}).entries)
        e.key: (e.value as num).toDouble(),
    },
    highlightLandmarks: <Landmark>[
      for (final i in (json['highlight'] as List<Object?>? ?? const []))
        ?Landmark.fromIndex((i as num).toInt()),
    ],
  );
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

  Map<String, Object?> toJson() => <String, Object?>{
    'priority': priority,
    'category': category.value,
    'description': description,
    'suggestedDrill': suggestedDrill,
    'exampleTimestampMs': exampleTimestampMs,
    'highlight': highlightLandmarks.map((l) => l.mpIndex).toList(),
  };

  factory Correction.fromJson(Map<String, Object?> json) => Correction(
    priority: (json['priority'] as num).toInt(),
    category: SkillCategory.fromValue(json['category'] as String),
    description: json['description'] as String,
    suggestedDrill: json['suggestedDrill'] as String?,
    exampleTimestampMs: (json['exampleTimestampMs'] as num?)?.toDouble(),
    highlightLandmarks: <Landmark>[
      for (final i in (json['highlight'] as List<Object?>? ?? const []))
        ?Landmark.fromIndex((i as num).toInt()),
    ],
  );
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

  Map<String, Object?> toJson() => <String, Object?>{
    'timestampMs': timestampMs,
    'reason': reason,
    'severity': severity.value,
  };

  factory FlaggedMoment.fromJson(Map<String, Object?> json) => FlaggedMoment(
    timestampMs: (json['timestampMs'] as num).toDouble(),
    reason: json['reason'] as String,
    severity: Severity.fromValue(json['severity'] as String),
  );
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

  Map<String, Object?> toJson() => <String, Object?>{
    'punchesThrown': punchesThrown,
    'guardReturnRate': guardReturnRate,
    'punchMix': punchMix,
    'values': values,
  };

  factory RoundMetrics.fromJson(Map<String, Object?> json) => RoundMetrics(
    punchesThrown: (json['punchesThrown'] as num?)?.toInt() ?? 0,
    guardReturnRate: (json['guardReturnRate'] as num?)?.toDouble(),
    punchMix: <String, int>{
      for (final e
          in (json['punchMix'] as Map<String, Object?>? ?? const {}).entries)
        e.key: (e.value as num).toInt(),
    },
    values: <String, double>{
      for (final e
          in (json['values'] as Map<String, Object?>? ?? const {}).entries)
        e.key: (e.value as num).toDouble(),
    },
  );
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

  Map<String, Object?> toJson() => <String, Object?>{
    'overallSummary': overallSummary,
    'specificObservations':
        specificObservations.map((o) => o.toJson()).toList(),
    'positiveNotes': positiveNotes,
    'correctionPriorities':
        correctionPriorities.map((c) => c.toJson()).toList(),
    'metrics': metrics.toJson(),
    'flaggedMoments': flaggedMoments.map((f) => f.toJson()).toList(),
  };

  factory RoundAnalysis.fromJson(Map<String, Object?> json) => RoundAnalysis(
    overallSummary: json['overallSummary'] as String,
    specificObservations: <Observation>[
      for (final o in (json['specificObservations'] as List<Object?>? ?? const []))
        Observation.fromJson((o as Map).cast<String, Object?>()),
    ],
    positiveNotes: <String>[
      for (final n in (json['positiveNotes'] as List<Object?>? ?? const []))
        n as String,
    ],
    correctionPriorities: <Correction>[
      for (final c in (json['correctionPriorities'] as List<Object?>? ?? const []))
        Correction.fromJson((c as Map).cast<String, Object?>()),
    ],
    metrics: RoundMetrics.fromJson(
      (json['metrics'] as Map?)?.cast<String, Object?>() ?? const {},
    ),
    flaggedMoments: <FlaggedMoment>[
      for (final f in (json['flaggedMoments'] as List<Object?>? ?? const []))
        FlaggedMoment.fromJson((f as Map).cast<String, Object?>()),
    ],
  );
}
