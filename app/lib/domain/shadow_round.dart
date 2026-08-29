import '../analysis/round_analysis.dart' as ra;
import 'session_record.dart';
import 'skill_category.dart';

/// Turns a standalone shadow-boxing round's analysis into a one-round
/// [SessionRecord], so it lands in History and the weekly category balance the
/// same way a guided session does.
///
/// A shadow round isn't built from exercises with category weights, so its time
/// is attributed with a fixed profile of what shadow boxing trains. Pure and
/// testable — no I/O.
SessionRecord shadowSessionRecord(
  ra.RoundAnalysis analysis, {
  required double durationMs,
  required String sessionId,
  required DateTime completedAt,
}) {
  final workSeconds = (durationMs / 1000).round();

  const weights = <SkillCategory, double>{
    SkillCategory.cardio: 0.20,
    SkillCategory.footwork: 0.20,
    SkillCategory.defence: 0.15,
    SkillCategory.headMovement: 0.15,
    SkillCategory.jab: 0.10,
    SkillCategory.straight: 0.10,
    SkillCategory.hooks: 0.10,
  };
  final categorySeconds = <String, int>{
    for (final e in weights.entries) e.key.key: (workSeconds * e.value).round(),
  };

  final correction = analysis.correctionPriorities.isNotEmpty
      ? analysis.correctionPriorities.first.description
      : null;
  final round = RoundSummary(
    segmentIndex: 0,
    title: 'Shadow round',
    roundNumber: 1,
    summary: analysis.overallSummary,
    topCorrection: correction,
    punchesThrown: analysis.metrics.punchesThrown,
    guardReturnRate: analysis.metrics.guardReturnRate,
  );

  return SessionRecord(
    sessionId: sessionId,
    templateName: 'Shadow boxing',
    completedAt: completedAt,
    totalSeconds: workSeconds,
    workSeconds: workSeconds,
    roundCount: 1,
    categorySeconds: categorySeconds,
    rounds: <RoundSummary>[round],
  );
}
