import 'dart:math' as math;

import '../domain/feature_flags.dart';
import 'checkpoint_evaluation.dart';
import 'checkpoints.dart';
import 'combination.dart';
import 'combination_analysis.dart';
import 'context.dart';
import 'drill.dart';
import 'engine.dart';
import 'pose.dart';
import 'punch.dart';
import 'round_analysis.dart';
import 'rule.dart';
import 'schools.dart';
import 'style_profiles.dart';

/// PoseOnlyAdapter — pose estimation + rules, no model. Mirror of
/// `src/boxing_coach/adapters/pose_only.py`, scoped to what v0.5 ships.
///
/// It runs the rule engine, then synthesises the observations into the
/// structured [RoundAnalysis] the coach speaks: a summary, prioritised
/// corrections, positive notes, metrics and flagged moments. Synthesis is
/// deterministic and template-based on purpose — the spec's v0.5 ships with no
/// API model in the loop.
///
/// Full parity with the Python reference: the style/school profile is resolved
/// from the drill, and `metrics.values` carries the round-profile features that
/// feed national-school classification.
class PoseOnlyAdapter {
  PoseOnlyAdapter({List<Rule>? rules})
    : _engine = RuleEngine(rules ?? defaultRules());

  final RuleEngine _engine;

  /// Which drill to suggest for a given fault category. Placeholder mapping — in
  /// the app this resolves against the exercise catalog.
  static const Map<String, String> _suggestedDrills = <String, String>{
    'defence':
        'Jab–return shadow drill: throw the jab, snap the hand back to your '
            'cheek before resetting.',
    'footwork':
        'In-and-out drill: two minutes never letting both feet stay planted '
            'for more than a beat.',
    'offence_straight':
        'Rear-hand rotation drill: throw the cross slow, exaggerating the '
            'hip/shoulder turn.',
    'head_movement': 'Slip-line drill: slip left/right after every jab.',
  };

  /// Observations the analyzers are less sure of than this are dropped from the
  /// user-facing report rather than shown as confident coaching (brief §12).
  /// The AI reasoning layer may still be handed them to weigh in context.
  static const double minReportedConfidence = 0.5;

  RoundAnalysis analyse(PoseSequence sequence, DrillContext drill) {
    final context = AnalysisContext(
      sequence: sequence,
      drill: drill,
      styleProfile: resolveProfile(drill.style, drill.school),
    );
    // A drill with a target (combination / technical work) is graded against
    // its technique checkpoints first; see checkpoints.dart.
    final target = drill.targetSequence;
    final checkpoints = target == null || target.isEmpty
        ? const <DrillCheckpoint>[]
        : Checkpoints.forSequence(target);
    final checkpointResults = evaluateCheckpoints(
      context.sequence,
      context.punches,
      drill.stance,
      context.bodyScale,
      checkpoints,
    );
    final tallies = tallyCheckpoints(checkpoints, checkpointResults);
    final checkpointFaults = _checkpointFaults(tallies);
    // A failed checkpoint supersedes the general rule's report of the same
    // fault: same miss, judged against the drill's standard.
    final supersededCodes = <String>{
      for (final o in checkpointFaults) o.code,
    };

    final allObservations = <Observation>[
      ...checkpointFaults,
      for (final o in _engine.run(context))
        if (!(o.severity.isFault && supersededCodes.contains(o.code))) o,
      ..._checkpointPositives(tallies),
    ];
    final observations = allObservations
        .where((o) => o.confidence >= minReportedConfidence)
        .toList();
    // Sub-threshold observations aren't shown to the user, but are kept for the
    // AI reasoning layer to weigh in context (brief §12).
    final lowConfidence = allObservations
        .where((o) => o.confidence < minReportedConfidence)
        .toList();

    final faults =
        observations.where((o) => o.severity.isFault).toList();
    final positives =
        observations.where((o) => o.severity == Severity.positive).toList();

    final combos = FeatureFlags.combinationDetection
        ? context.combinations
        : const <Combination>[];
    final comboAnalyses = <CombinationAnalysis>[
      for (final combo in combos)
        analyzeCombination(
          context.sequence,
          context.punches,
          combo,
          context.drill.stance,
          context.bodyScale,
          checkpointResults: checkpointResults,
        ),
    ];

    return RoundAnalysis(
      overallSummary: _summary(context, faults, positives),
      specificObservations: observations,
      positiveNotes: positives.map((o) => o.coachingText).toList(),
      correctionPriorities: _corrections(faults),
      metrics: _metrics(context, faults, comboAnalyses),
      flaggedMoments: _flagged(faults),
      combinations: combos,
      combinationAnalyses: comboAnalyses,
      lowConfidenceObservations: lowConfidence,
      sessionType: drill.sessionType,
      checkpointTallies: tallies,
    );
  }

  String _summary(
    AnalysisContext context,
    List<Observation> faults,
    List<Observation> positives,
  ) {
    final n = context.punches.length;
    if (faults.isEmpty && positives.isNotEmpty) {
      return 'Clean round — $n punches thrown and nothing to correct. Keep it '
          'there.';
    }
    if (faults.isEmpty && positives.isEmpty) {
      return '$n punches thrown. Nothing flagged, but not much to work with '
          'either.';
    }
    final top = faults.first;
    final extra =
        faults.length > 1 ? ' plus ${faults.length - 1} other point(s)' : '';
    return '$n punches thrown. Main thing to fix: ${top.coachingText}$extra';
  }

  List<Correction> _corrections(List<Observation> faults) {
    final seen = <String>{};
    final corrections = <Correction>[];
    var priority = 1;
    for (final obs in faults) {
      // Already sorted worst-first, drill checkpoints ahead of general faults.
      // Each failed checkpoint is its own correction; general faults keep one
      // per category.
      if (obs.ruleId != checkpointRuleId) {
        if (seen.contains(obs.category.value)) continue;
        seen.add(obs.category.value);
      }
      corrections.add(
        Correction(
          priority: priority,
          category: obs.category,
          description: obs.coachingText,
          suggestedDrill: _suggestedDrills[obs.category.value],
          exampleTimestampMs: obs.timestampMs,
          highlightLandmarks: obs.highlightLandmarks,
        ),
      );
      priority++;
    }
    return corrections;
  }

  RoundMetrics _metrics(
    AnalysisContext context,
    List<Observation> faults,
    List<CombinationAnalysis> comboAnalyses,
  ) {
    final n = context.punches.length;
    final guardReturnFaults = faults
        .where((o) => o.ruleId == 'guard_return' && o.severity.isFault)
        .length;
    double? guardRate;
    if (n > 0) {
      final capped = guardReturnFaults < n ? guardReturnFaults : n;
      guardRate = _round(1.0 - capped / n, 3);
    }
    final features = roundFeatureValues(
      context.roundProfile,
      context.punches,
      context.drill.stance,
    );
    return RoundMetrics(
      punchesThrown: n,
      guardReturnRate: guardRate,
      punchMix: _punchMix(context),
      values: <String, double>{
        'body_scale': _round(context.bodyScale, 4),
        if (FeatureFlags.combinationDetection) ...<String, double>{
          'combinations_detected': comboAnalyses.length.toDouble(),
          // Combination Execution component score (brief §27) — mean of the
          // per-combination scores. Omitted when no combination was thrown.
          if (comboAnalyses.isNotEmpty)
            'combination_execution_score': _round(
              comboAnalyses.map((c) => c.score).reduce((a, b) => a + b) /
                  comboAnalyses.length,
              1,
            ),
        },
        for (final e in features.entries) e.key: _round(e.value, 3),
      },
    );
  }

  Map<String, int> _punchMix(AnalysisContext context) {
    final stance = context.drill.stance;
    final mix = <String, int>{};
    for (final punch in context.punches) {
      final name = punchName(punch.punchType, punch.side, stance);
      mix[name] = (mix[name] ?? 0) + 1;
    }
    return mix;
  }

  List<FlaggedMoment> _flagged(List<Observation> faults) {
    final moments = <FlaggedMoment>[
      for (final o in faults)
        if (o.timestampMs != null)
          FlaggedMoment(
            timestampMs: o.timestampMs!,
            reason: o.coachingText,
            severity: o.severity,
          ),
    ]..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return moments;
  }

  /// Rule id carried by checkpoint observations.
  static const String checkpointRuleId = 'checkpoint';

  /// One fault per checkpoint that failed on any graded rep, worst fail rate
  /// first. Severity scales with how often it failed: most reps → major.
  List<Observation> _checkpointFaults(List<CheckpointTally> tallies) {
    final faults = <Observation>[
      for (final t in tallies)
        if (t.failed > 0)
          Observation(
            ruleId: checkpointRuleId,
            code: t.checkpoint.checkpoint.faultCode,
            category: _categoryForPunch(t.checkpoint.punchNumber),
            severity: _severityForFailRate(t.failed / t.graded),
            coachingText: '${t.checkpoint.checkpoint.failCue} '
                '(${t.failed} of ${t.graded} reps.)',
            confidence: t.confidence,
            timestampMs: t.firstFailureMs,
            metrics: <String, double>{
              'fail_rate': _round(t.failed / t.graded, 3),
              'reps_graded': t.graded.toDouble(),
            },
          ),
    ]..sort((a, b) {
        final bySeverity = b.severity.rank.compareTo(a.severity.rank);
        if (bySeverity != 0) return bySeverity;
        return (b.metrics['fail_rate'] ?? 0).compareTo(a.metrics['fail_rate'] ?? 0);
      });
    return faults;
  }

  /// Checkpoints held on nearly every graded rep (at least three) — worth
  /// telling the fighter, in the drill's own terms.
  List<Observation> _checkpointPositives(List<CheckpointTally> tallies) {
    return <Observation>[
      for (final t in tallies)
        if (t.graded >= 3 && (t.passRate ?? 0) >= 0.8)
          Observation(
            ruleId: checkpointRuleId,
            code: t.checkpoint.checkpoint.faultCode,
            category: _categoryForPunch(t.checkpoint.punchNumber),
            severity: Severity.positive,
            coachingText: '${t.checkpoint.punchName}: '
                '${t.checkpoint.checkpoint.label.toLowerCase()} — '
                '${t.passed} of ${t.graded} reps.',
            confidence: t.confidence,
          ),
    ];
  }

  static Severity _severityForFailRate(double rate) {
    if (rate >= 0.5) return Severity.major;
    if (rate >= 0.25) return Severity.moderate;
    return Severity.minor;
  }

  static SkillCategory _categoryForPunch(int number) => switch (number) {
    1 => SkillCategory.jab,
    2 => SkillCategory.straight,
    3 || 4 => SkillCategory.hooks,
    5 || 6 => SkillCategory.uppercuts,
    _ => SkillCategory.combinations,
  };

  static double _round(double value, int places) {
    final factor = math.pow(10, places).toDouble();
    return (value * factor).round() / factor;
  }
}
