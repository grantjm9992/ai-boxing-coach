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
    final observations = _engine
        .run(context)
        .where((o) => o.confidence >= minReportedConfidence)
        .toList();

    final faults =
        observations.where((o) => o.severity.isFault).toList();
    final positives =
        observations.where((o) => o.severity == Severity.positive).toList();

    return RoundAnalysis(
      overallSummary: _summary(context, faults, positives),
      specificObservations: observations,
      positiveNotes: positives.map((o) => o.coachingText).toList(),
      correctionPriorities: _corrections(faults),
      metrics: _metrics(context, faults),
      flaggedMoments: _flagged(faults),
      sessionType: drill.sessionType,
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
      // already sorted worst-first
      if (seen.contains(obs.category.value)) continue;
      seen.add(obs.category.value);
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

  RoundMetrics _metrics(AnalysisContext context, List<Observation> faults) {
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

  static double _round(double value, int places) {
    final factor = <int, double>{3: 1000.0, 4: 10000.0}[places]!;
    return (value * factor).round() / factor;
  }
}
