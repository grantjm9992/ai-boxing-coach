import 'combination_analysis.dart';

/// Combination-drill evaluation (brief §15): comparing what the user was asked
/// to throw against what was actually detected, per attempt and in aggregate.
///
/// A drill round is repetitions of one target combination. Each detected
/// combination in the round is one attempt; the analyzer already scored its
/// execution (Phase 4), so this layer only adds the sequence comparison and the
/// aggregate roll-up.

/// One repetition the user threw.
class DrillAttempt {
  const DrillAttempt({
    required this.detected,
    required this.sequenceMatch,
    required this.executionScore,
    required this.startMs,
    required this.endMs,
    this.issues = const <CombinationIssue>[],
  });

  /// The numbers actually detected for this attempt, e.g. `[1, 2, 3]`.
  final List<int> detected;

  /// Whether [detected] is exactly the target sequence.
  final bool sequenceMatch;

  /// Execution score (0–100) from the combination analyzer.
  final int executionScore;

  final double startMs;
  final double endMs;
  final List<CombinationIssue> issues;
}

/// The result of a whole drill round.
class DrillResult {
  const DrillResult({required this.expected, required this.attempts});

  final List<int> expected;
  final List<DrillAttempt> attempts;

  int get totalAttempts => attempts.length;

  int get matchedCount =>
      attempts.where((a) => a.sequenceMatch).length;

  /// Fraction of attempts that threw the right sequence (0 when none tried).
  double get matchRate =>
      attempts.isEmpty ? 0 : matchedCount / attempts.length;

  /// Mean execution score across the attempts that matched the sequence — the
  /// honest measure of drill quality (a mis-thrown combination shouldn't lift
  /// or sink the technique score). Null when nothing matched.
  double? get averageScore {
    final matched = attempts.where((a) => a.sequenceMatch).toList();
    if (matched.isEmpty) return null;
    final sum = matched.fold<int>(0, (t, a) => t + a.executionScore);
    return sum / matched.length;
  }
}

bool _sameSequence(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Builds a [DrillResult] for [expected] from the round's combination analyses.
DrillResult evaluateDrill(
  List<int> expected,
  List<CombinationAnalysis> analyses,
) {
  return DrillResult(
    expected: expected,
    attempts: <DrillAttempt>[
      for (final analysis in analyses)
        DrillAttempt(
          detected: analysis.combination.sequence,
          sequenceMatch:
              _sameSequence(analysis.combination.sequence, expected),
          executionScore: analysis.score,
          startMs: analysis.combination.startMs,
          endMs: analysis.combination.endMs,
          issues: analysis.issues,
        ),
    ],
  );
}
