import 'session_plan.dart';
import 'skill_category.dart';

/// A one-line record of a round within a completed session, for the history and
/// review screens.
class RoundSummary {
  const RoundSummary({
    required this.segmentIndex,
    required this.title,
    this.roundNumber,
    this.summary,
    this.topCorrection,
    this.punchesThrown,
    this.guardReturnRate,
  });

  final int segmentIndex;
  final String title;
  final int? roundNumber;

  /// The analysis summary, or null if the round wasn't analysed (no camera).
  final String? summary;
  final String? topCorrection;
  final int? punchesThrown;
  final double? guardReturnRate;

  Map<String, Object?> toJson() => <String, Object?>{
    'segmentIndex': segmentIndex,
    'title': title,
    'roundNumber': roundNumber,
    'summary': summary,
    'topCorrection': topCorrection,
    'punchesThrown': punchesThrown,
    'guardReturnRate': guardReturnRate,
  };

  factory RoundSummary.fromJson(Map<String, Object?> json) => RoundSummary(
    segmentIndex: (json['segmentIndex'] as num).toInt(),
    title: json['title'] as String? ?? 'Round',
    roundNumber: (json['roundNumber'] as num?)?.toInt(),
    summary: json['summary'] as String?,
    topCorrection: json['topCorrection'] as String?,
    punchesThrown: (json['punchesThrown'] as num?)?.toInt(),
    guardReturnRate: (json['guardReturnRate'] as num?)?.toDouble(),
  );
}

/// A completed session, persisted for the history list and the weekly category
/// balance. This is the spec's session history, kept as JSON per session rather
/// than in SQLite — same data, simpler and testable without a native DB.
class SessionRecord {
  const SessionRecord({
    required this.sessionId,
    required this.templateName,
    required this.completedAt,
    required this.totalSeconds,
    required this.workSeconds,
    required this.roundCount,
    required this.categorySeconds,
    this.rounds = const <RoundSummary>[],
  });

  final String sessionId;
  final String templateName;
  final DateTime completedAt;
  final int totalSeconds;
  final int workSeconds;
  final int roundCount;

  /// Weighted working seconds per skill-category key — the balance-view input.
  final Map<String, int> categorySeconds;

  final List<RoundSummary> rounds;

  /// Builds a record from the plan that was run plus whatever rounds were
  /// analysed (segment index -> a one-line summary).
  factory SessionRecord.fromPlan(
    SessionPlan plan, {
    required String sessionId,
    required DateTime completedAt,
    List<RoundSummary> rounds = const <RoundSummary>[],
  }) {
    return SessionRecord(
      sessionId: sessionId,
      templateName: plan.template.name,
      completedAt: completedAt,
      totalSeconds: plan.totalDuration.inSeconds,
      workSeconds: plan.workDuration.inSeconds,
      roundCount: plan.roundCount,
      categorySeconds: <String, int>{
        for (final entry in plan.categoryBreakdown.entries)
          entry.key.key: entry.value.inSeconds,
      },
      rounds: rounds,
    );
  }

  /// The category balance as the UI's [CategoryBalance] widget wants it.
  Map<SkillCategory, Duration> get categoryBreakdown => <SkillCategory, Duration>{
    for (final entry in categorySeconds.entries)
      ?SkillCategory.fromKey(entry.key): Duration(seconds: entry.value),
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'templateName': templateName,
    'completedAt': completedAt.toIso8601String(),
    'totalSeconds': totalSeconds,
    'workSeconds': workSeconds,
    'roundCount': roundCount,
    'categorySeconds': categorySeconds,
    'rounds': rounds.map((r) => r.toJson()).toList(),
  };

  static SessionRecord? fromJson(Map<String, Object?> json) {
    final completedAt = DateTime.tryParse(json['completedAt'] as String? ?? '');
    final sessionId = json['sessionId'] as String?;
    if (completedAt == null || sessionId == null) return null;
    return SessionRecord(
      sessionId: sessionId,
      templateName: json['templateName'] as String? ?? 'Session',
      completedAt: completedAt,
      totalSeconds: (json['totalSeconds'] as num?)?.toInt() ?? 0,
      workSeconds: (json['workSeconds'] as num?)?.toInt() ?? 0,
      roundCount: (json['roundCount'] as num?)?.toInt() ?? 0,
      categorySeconds: <String, int>{
        for (final e in (json['categorySeconds'] as Map<String, Object?>? ??
                const <String, Object?>{})
            .entries)
          e.key: (e.value as num).toInt(),
      },
      rounds: <RoundSummary>[
        for (final r in (json['rounds'] as List<Object?>? ?? const []))
          RoundSummary.fromJson((r as Map).cast<String, Object?>()),
      ],
    );
  }
}
