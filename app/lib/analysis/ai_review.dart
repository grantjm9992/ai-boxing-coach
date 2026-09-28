import 'ai_coach_report.dart';
import 'round_analysis.dart';

/// Findings the AI is less sure of than this aren't shown. The model is asked
/// to calibrate: ~0.9 seen clearly and repeatedly, ~0.7 seen clearly once,
/// below 0.5 a guess. 0.6 keeps "seen clearly at least once".
const double kMinFindingConfidence = 0.6;

/// The most findings (and so moments) a round shows.
const int kMaxFindings = 7;

/// Two findings with the same code this close together are the same moment.
const double _duplicateWindowSeconds = 1.5;

/// Folds a Full AI review ([AiCoachReport]) into the rules' [RoundAnalysis].
///
/// In Full AI review the model has watched the whole round with the rules'
/// measurements and flags in front of it, so its findings are the verdict: they
/// become the round's corrections (and so its moments — the review screen,
/// synced keyframes and History all build moments from the corrections). The
/// rules' raw observations are kept untouched for evaluation. Pure, so the
/// merge is unit-tested without a model.
class AiReview {
  const AiReview._();

  /// The findings worth showing: confident, with at least one timestamp inside
  /// the round (a moment needs a frame, and an out-of-range time is a sign the
  /// model is guessing), de-duplicated, worst first, capped at [max].
  static List<AiPriorityIssue> shownFindings(
    AiCoachReport report, {
    double minConfidence = kMinFindingConfidence,
    int max = kMaxFindings,
    double? durationSeconds,
  }) {
    bool inRound(double t) =>
        t >= 0 && (durationSeconds == null || t <= durationSeconds + 0.5);

    final candidates = <AiPriorityIssue>[
      for (final issue in report.priorityIssues)
        if (issue.severity.isFault && issue.confidence >= minConfidence)
          if (issue.timestamps.where(inRound).isNotEmpty)
            AiPriorityIssue(
              code: issue.code,
              severity: issue.severity,
              confidence: issue.confidence,
              timestamps: issue.timestamps.where(inRound).toList(),
              observation: issue.observation,
              whyItMatters: issue.whyItMatters,
              correction: issue.correction,
              suggestedDrill: issue.suggestedDrill,
            ),
    ]..sort((a, b) {
        final bySeverity = b.severity.rank.compareTo(a.severity.rank);
        return bySeverity != 0 ? bySeverity : b.confidence.compareTo(a.confidence);
      });

    final kept = <AiPriorityIssue>[];
    for (final issue in candidates) {
      final duplicate = kept.any((k) =>
          k.code == issue.code &&
          (k.timestamps.first - issue.timestamps.first).abs() <
              _duplicateWindowSeconds);
      if (!duplicate) kept.add(issue);
      if (kept.length == max) break;
    }
    return kept;
  }

  /// The moment label for a finding: what was seen, then the cue — the same
  /// shape as the rules' coaching text.
  static String labelFor(AiPriorityIssue issue) {
    final observation = issue.observation.trim();
    final correction = issue.correction.trim();
    if (observation.isEmpty) return correction;
    final separator = RegExp(r'[.!?]$').hasMatch(observation) ? ' ' : '. ';
    return '$observation$separator$correction';
  }

  /// The skill category a taxonomy code trains (annotations/taxonomy/codes.json
  /// families), for the correction's category.
  static SkillCategory categoryFor(String code) {
    final family = code.split('_').first.toUpperCase();
    switch (family) {
      case 'ROT':
        return SkillCategory.straight;
      case 'BAL':
      case 'FOOT':
      case 'LEAN':
      case 'POS':
        return SkillCategory.footwork;
      case 'HEAD':
        return SkillCategory.headMovement;
      case 'TENSE':
        return SkillCategory.rhythm;
      case 'COMBO':
        return SkillCategory.combinations;
      case 'GUARD':
      case 'REC':
      default:
        return SkillCategory.defence;
    }
  }

  /// [rules] with [report] applied: the confident findings replace the rules'
  /// corrections and flagged moments, the model's strengths replace the rules'
  /// positive notes (they can contradict what the model saw), the summary line
  /// names the model's top finding, and the model's spoken read becomes the
  /// coaching text. The full report is kept on [RoundAnalysis.aiReport].
  static RoundAnalysis apply(
    RoundAnalysis rules,
    AiCoachReport report, {
    double? durationSeconds,
    double minConfidence = kMinFindingConfidence,
    int max = kMaxFindings,
  }) {
    final findings = shownFindings(
      report,
      minConfidence: minConfidence,
      max: max,
      durationSeconds: durationSeconds,
    );
    final corrections = <Correction>[
      for (var i = 0; i < findings.length; i++)
        Correction(
          priority: i + 1,
          category: categoryFor(findings[i].code),
          description: labelFor(findings[i]),
          suggestedDrill: findings[i].suggestedDrill.trim().isEmpty
              ? null
              : findings[i].suggestedDrill.trim(),
          exampleTimestampMs: findings[i].timestamps.first * 1000,
        ),
    ];
    final strengths = <String>[
      for (final s in report.strengths)
        if (s.trim().isNotEmpty) s.trim(),
    ].take(4).toList();

    return RoundAnalysis(
      overallSummary: _summary(rules.metrics.punchesThrown, findings),
      specificObservations: rules.specificObservations,
      positiveNotes: strengths.isNotEmpty ? strengths : rules.positiveNotes,
      correctionPriorities: corrections,
      metrics: rules.metrics,
      flaggedMoments: const <FlaggedMoment>[],
      combinations: rules.combinations,
      combinationAnalyses: rules.combinationAnalyses,
      lowConfidenceObservations: rules.lowConfidenceObservations,
      modelCoaching: report.summary,
      aiReport: report,
      analysisVersion: rules.analysisVersion,
      sessionType: rules.sessionType,
    );
  }

  static String _summary(int punches, List<AiPriorityIssue> findings) {
    if (findings.isEmpty) {
      return '$punches punches thrown. Nothing the AI coach was confident '
          'enough to flag — keep it there.';
    }
    final top = findings.first.correction.trim();
    final extra = findings.length > 1
        ? ' plus ${findings.length - 1} other point(s)'
        : '';
    return '$punches punches thrown. Main thing to fix: $top$extra';
  }
}
