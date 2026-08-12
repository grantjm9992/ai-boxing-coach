import '../context.dart';
import '../geometry.dart' as geo;
import '../landmarks.dart';
import '../round_analysis.dart';
import '../rule.dart';

/// Rule: are the hands kept up when *not* punching? Mirror of
/// `src/boxing_coach/analysis/rules/hands_up.py`.
///
/// Distinct from guard return (the moment after a punch). This is the baseline
/// habit: between exchanges, do the wrists stay up near the head, or drift below
/// the shoulder line? We measure the fraction of idle frames spent hands-down.
class HandsUpConfig {
  const HandsUpConfig({
    this.dropMargin = 0.10,
    this.maxDownFraction = 0.25,
    this.checkLead = true,
    this.checkRear = true,
    this.relativeToBaseline = false,
    this.baselineWindowMs = 1000.0,
    this.excuseWhileMoving = false,
    this.movingSpeed = 0.6,
  });

  final double dropMargin;
  final double maxDownFraction;
  final bool checkLead;
  final bool checkRear;
  final bool relativeToBaseline;
  final double baselineWindowMs;
  final bool excuseWhileMoving;
  final double movingSpeed;

  HandsUpConfig copyWith({
    bool? relativeToBaseline,
    bool? excuseWhileMoving,
  }) => HandsUpConfig(
    dropMargin: dropMargin,
    maxDownFraction: maxDownFraction,
    checkLead: checkLead,
    checkRear: checkRear,
    relativeToBaseline: relativeToBaseline ?? this.relativeToBaseline,
    baselineWindowMs: baselineWindowMs,
    excuseWhileMoving: excuseWhileMoving ?? this.excuseWhileMoving,
    movingSpeed: movingSpeed,
  );
}

class HandsUpRule extends Rule {
  HandsUpRule([HandsUpConfig? config]) : _cfg = config ?? const HandsUpConfig();

  final HandsUpConfig _cfg;

  @override
  String get id => 'hands_up';

  @override
  List<Observation> evaluate(AnalysisContext context) {
    final cfg = context.styleProfile.configFor(id, _cfg);
    final idle = _idleFrameIndices(context);
    if (idle.isEmpty) return <Observation>[];

    final stance = context.drill.stance;
    final checked = <Side>{};
    if (cfg.checkLead) checked.add(stance.lead);
    if (cfg.checkRear) checked.add(stance.rear);

    final observations = <Observation>[];
    for (final side in Side.values) {
      if (!checked.contains(side)) continue;
      final (downFraction, worstMs) = _downFraction(context, side, idle, cfg);
      if (downFraction == null) continue;
      if (downFraction > cfg.maxDownFraction) {
        final hand = side == stance.lead ? 'lead' : 'rear';
        observations.add(
          Observation(
            ruleId: id,
            category: SkillCategory.defence,
            severity: downFraction > 0.5 ? Severity.moderate : Severity.minor,
            coachingText:
                'Your $hand hand keeps drifting down between punches. Glue it '
                "to your cheek — you're open to the counter.",
            timestampMs: worstMs,
            metrics: <String, double>{'down_fraction': downFraction},
            highlightLandmarks: <Landmark>[side.wrist],
          ),
        );
      }
    }
    return observations;
  }

  /// Frames that aren't part of any punch (start..end inclusive).
  List<int> _idleFrameIndices(AnalysisContext context) {
    final punching = <int>{};
    for (final p in context.punches) {
      for (var i = p.startIndex; i <= p.endIndex; i++) {
        punching.add(i);
      }
    }
    return <int>[
      for (var i = 0; i < context.sequence.length; i++)
        if (!punching.contains(i)) i,
    ];
  }

  (double?, double?) _downFraction(
    AnalysisContext context,
    Side side,
    List<int> idle,
    HandsUpConfig cfg,
  ) {
    final seq = context.sequence;
    final scale = context.bodyScale;
    final speeds = cfg.excuseWhileMoving ? context.stanceSpeed : null;
    final baseline =
        cfg.relativeToBaseline ? _baselineDrop(context, side, idle, cfg) : 0.0;
    var considered = 0;
    var down = 0;
    double? worstMs;
    var worstDrop = 0.0;
    for (final i in idle) {
      if (speeds != null && speeds[i] > cfg.movingSpeed) continue;
      final frame = seq.frames[i];
      final wrist = geo.framePoint(frame, side.wrist);
      final shoulder = geo.framePoint(frame, side.shoulder);
      if (wrist.any((v) => v.isNaN) || shoulder.any((v) => v.isNaN)) continue;
      considered++;
      final drop = (wrist[1] - shoulder[1]) / scale - baseline;
      if (drop > cfg.dropMargin) {
        down++;
        if (drop > worstDrop) {
          worstDrop = drop;
          worstMs = frame.timestampMs;
        }
      }
    }
    if (considered == 0) return (null, null);
    return (down / considered, worstMs);
  }

  /// Median wrist-below-shoulder over the fighter's settled early carriage — the
  /// reference a low hand is judged against under Soviet (relativeToBaseline).
  double _baselineDrop(
    AnalysisContext context,
    Side side,
    List<int> idle,
    HandsUpConfig cfg,
  ) {
    final seq = context.sequence;
    final scale = context.bodyScale;
    if (idle.isEmpty) return 0.0;
    final t0 = seq.frames[idle.first].timestampMs;
    final early = <double>[];
    final overall = <double>[];
    for (final i in idle) {
      final frame = seq.frames[i];
      final wrist = geo.framePoint(frame, side.wrist);
      final shoulder = geo.framePoint(frame, side.shoulder);
      if (wrist.any((v) => v.isNaN) || shoulder.any((v) => v.isNaN)) continue;
      final drop = (wrist[1] - shoulder[1]) / scale;
      overall.add(drop);
      if (frame.timestampMs - t0 <= cfg.baselineWindowMs) early.add(drop);
    }
    final drops = early.isNotEmpty ? early : overall;
    return drops.isNotEmpty ? geo.nanMedian(drops) : 0.0;
  }
}
