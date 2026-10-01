import '../../analysis/ai_coach_report.dart';
import '../analysis/fighter_analysis.dart';
import '../analysis/sparring_analyzer.dart';
import '../model/fighter.dart';
import 'sparring_report.dart';

/// Folds the AI coach's [SparringAiReport] into a round's on-device analysis:
/// per fighter, the AI's confident findings become the shown findings (it
/// watched the video with the measurements in front of it, so it has the final
/// say); its strengths and summary replace the rules'. Measurements — punches,
/// output, interaction — stay the on-device ones. Pure.
class SparringReview {
  const SparringReview._();

  /// Same window as the single-person review: one fault reported twice this
  /// close together is one moment.
  static const double duplicateWindowSeconds = 1.5;

  static SparringRoundAnalysis apply(
    SparringRoundAnalysis analysis,
    SparringAiReport report, {
    double minConfidence = kSparringMinConfidence,
    int max = kSparringMaxFindings,
  }) {
    final seconds = analysis.durationMs / 1000;
    final fighters = <FighterLabel, FighterAnalysis>{};
    for (final label in FighterLabel.values) {
      final current = analysis.fighter(label);
      final ai = report.fighter(label);
      final strengths = <String>[
        for (final s in ai.strengths)
          if (s.trim().isNotEmpty) s.trim(),
      ].take(4).toList();
      fighters[label] = current.copyWith(
        findings: shownFindings(
          ai.issues,
          durationSeconds: seconds,
          minConfidence: minConfidence,
          max: max,
        ),
        strengths: strengths.isEmpty ? current.strengths : strengths,
        summary: ai.summary.trim().isEmpty ? null : ai.summary.trim(),
      );
    }
    return analysis.copyWith(
      fighters: fighters,
      ai: report,
      clearAiError: true,
      aiStale: false,
    );
  }

  /// Confident faults with a moment inside the round, de-duplicated, worst
  /// first, capped.
  static List<FighterFinding> shownFindings(
    List<AiPriorityIssue> issues, {
    double? durationSeconds,
    double minConfidence = kSparringMinConfidence,
    int max = kSparringMaxFindings,
  }) {
    bool inRound(double t) =>
        t >= 0 && (durationSeconds == null || t <= durationSeconds + 0.5);
    final candidates = <AiPriorityIssue>[
      for (final i in issues)
        if (i.severity.isFault &&
            i.confidence >= minConfidence &&
            i.timestamps.any(inRound))
          i,
    ]..sort((a, b) {
        final bySeverity = b.severity.rank.compareTo(a.severity.rank);
        return bySeverity != 0 ? bySeverity : b.confidence.compareTo(a.confidence);
      });

    final kept = <FighterFinding>[];
    for (final issue in candidates) {
      final at = issue.timestamps.firstWhere(inRound);
      final duplicate = kept.any((k) =>
          k.code == issue.code &&
          k.timestampMs != null &&
          (k.timestampMs! / 1000 - at).abs() < duplicateWindowSeconds);
      if (duplicate) continue;
      kept.add(FighterFinding(
        code: issue.code,
        severity: issue.severity,
        confidence: issue.confidence,
        text: _label(issue),
        source: 'ai',
        timestampMs: at * 1000,
        drill: issue.suggestedDrill.trim().isEmpty ? null : issue.suggestedDrill.trim(),
      ));
      if (kept.length == max) break;
    }
    return kept;
  }

  static String _label(AiPriorityIssue issue) {
    final observation = issue.observation.trim();
    final correction = issue.correction.trim();
    if (observation.isEmpty) return correction;
    final separator = RegExp(r'[.!?]$').hasMatch(observation) ? ' ' : '. ';
    return '$observation$separator$correction';
  }
}
