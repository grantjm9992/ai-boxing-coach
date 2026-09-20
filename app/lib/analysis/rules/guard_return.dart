import '../context.dart';
import '../error_codes.dart';
import '../features.dart';
import '../geometry.dart' as geo;
import '../landmarks.dart';
import '../pose.dart';
import '../round_analysis.dart';
import '../rule.dart';

/// Rule: does the hand come back to guard after a punch? Mirror of
/// `src/boxing_coach/analysis/rules/guard_return.py` — the flagship check, and
/// the first correction v0.5 turns on.
///
/// For each detected punch we ask whether the wrist came back to *where it
/// launched the punch from* — the fighter's own guard — within a short window.
/// Measuring against the launch position rather than an absolute head/cheek
/// position means a deliberately low or extended carry (a range-finder, a Philly
/// shell) is not flagged; only a hand that ends somewhere it did not start.
class GuardReturnConfig {
  const GuardReturnConfig({
    this.returnRadius = 0.5,
    this.dropMargin = 0.15,
    this.extendedReach = 1.0,
    this.returnWindowMs = 500.0,
    this.returnSpeedFactor = 1.5,
    this.maxReturnWindowMs = 900.0,
    this.healthyReturnRate = 0.8,
    this.checkLead = true,
    this.checkRear = true,
    this.excuseWhileMoving = true,
    this.movingSpeed = 0.6,
    this.requireFullReturnWindow = true,
  });

  /// "Returned" if the hand comes back within this many torso-lengths of where
  /// it launched the punch from (its own guard).
  final double returnRadius;

  /// After the window, a wrist this far below its launch height reads as dropped.
  final double dropMargin;

  /// ...and a wrist still this far from its shoulder reads as left hanging out.
  final double extendedReach;

  /// Base/minimum return time (ms). The effective window scales with throw speed.
  final double returnWindowMs;

  /// The return window is judged relative to the punch speed: a slow, deliberate
  /// punch earns a slow return. Effective window = clamp(extensionMs * factor,
  /// returnWindowMs, maxReturnWindowMs). 0 restores the fixed window.
  final double returnSpeedFactor;
  final double maxReturnWindowMs;

  /// Below this fraction of returning punches, flag a round-level fault.
  final double healthyReturnRate;

  final bool checkLead;
  final bool checkRear;

  /// Range vs movement: don't fault a hand that ends low/away when the fighter
  /// steps out through the return — that's distance management. A planted fighter
  /// is still judged. On by default so movement counts for every style.
  final bool excuseWhileMoving;

  /// Stance-centre speed (torso-lengths/sec) above which the fighter counts as
  /// stepping in/out during the return.
  final double movingSpeed;

  /// When the clip ends before the return window closes (a punch thrown right at
  /// the buzzer), we never see whether the hand came back — real footage fires a
  /// false "didn't return" on the last punch of every round. A truncated window
  /// only survives as a positively-observed drop; a slow/extended verdict there
  /// is just "ran out of frames" and is dropped.
  final bool requireFullReturnWindow;

  GuardReturnConfig copyWith({bool? excuseWhileMoving}) => GuardReturnConfig(
    returnRadius: returnRadius,
    dropMargin: dropMargin,
    extendedReach: extendedReach,
    returnWindowMs: returnWindowMs,
    returnSpeedFactor: returnSpeedFactor,
    maxReturnWindowMs: maxReturnWindowMs,
    healthyReturnRate: healthyReturnRate,
    checkLead: checkLead,
    checkRear: checkRear,
    excuseWhileMoving: excuseWhileMoving ?? this.excuseWhileMoving,
    movingSpeed: movingSpeed,
    requireFullReturnWindow: requireFullReturnWindow,
  );
}

class GuardReturnRule extends Rule {
  GuardReturnRule([GuardReturnConfig? config])
    : _cfg = config ?? const GuardReturnConfig();

  final GuardReturnConfig _cfg;

  @override
  String get id => 'guard_return';

  @override
  Set<String> get focusTags =>
      const <String>{'jab', 'straight', 'combinations', 'defence'};

  @override
  List<Observation> evaluate(AnalysisContext context) {
    final cfg = context.styleProfile.configFor(id, _cfg);
    final seq = context.sequence;
    final checked = _checkedSides(context, cfg);
    final observations = <Observation>[];
    var returned = 0;
    var total = 0;

    for (final punch in context.punches) {
      if (!checked.contains(punch.side)) continue;
      total++;
      final verdict = _classifyReturn(context, punch, cfg);
      if (verdict == null) {
        returned++;
        continue;
      }
      final (failureMode, worstFrame) = verdict;
      observations.add(
        Observation(
          ruleId: id,
          code: FaultCode.recHandNotReturned,
          category: SkillCategory.defence,
          severity: Severity.moderate,
          coachingText: _coachingText(context.drill.stance, punch.side, failureMode),
          timestampMs: seq.frames[worstFrame].timestampMs,
          metrics: <String, double>{'peak_reach': punch.peakReach},
          highlightLandmarks: <Landmark>[punch.side.wrist],
        ),
      );
    }

    if (total > 0) {
      final rate = returned / total;
      if (rate >= cfg.healthyReturnRate && observations.isEmpty) {
        observations.add(
          Observation(
            ruleId: id,
            category: SkillCategory.defence,
            severity: Severity.positive,
            coachingText:
                'Clean guard return all round — hands came straight back to guard.',
            metrics: <String, double>{'guard_return_rate': rate},
          ),
        );
      }
    }
    return observations;
  }

  Set<Side> _checkedSides(AnalysisContext context, GuardReturnConfig cfg) {
    final stance = context.drill.stance;
    final sides = <Side>{};
    if (cfg.checkLead) sides.add(stance.lead);
    if (cfg.checkRear) sides.add(stance.rear);
    return sides;
  }

  /// Null if the hand returns to its launch guard in time; else (mode, frame).
  (String, int)? _classifyReturn(
    AnalysisContext context,
    PunchEvent punch,
    GuardReturnConfig cfg,
  ) {
    final seq = context.sequence;
    final scale = context.bodyScale;
    // The guard reference is where the hand launched the punch from.
    final ref = geo.framePoint(seq.frames[punch.startIndex], punch.side.wrist);
    if (ref.any((v) => v.isNaN)) return null; // no usable guard reference

    final deadline = seq.frames[punch.endIndex].timestampMs +
        _returnWindowMs(seq, punch, cfg);

    var bestDist = double.infinity;
    var worstDist = double.negativeInfinity;
    var worstFrame = punch.peakIndex;
    for (var i = punch.peakIndex; i < seq.length; i++) {
      final frame = seq.frames[i];
      if (frame.timestampMs > deadline) break;
      final wrist = geo.framePoint(frame, punch.side.wrist);
      if (wrist.any((v) => v.isNaN)) continue;
      final dist = geo.distance(wrist, ref) / scale;
      if (dist < bestDist) bestDist = dist;
      if (dist > worstDist) {
        worstDist = dist;
        worstFrame = i;
      }
    }

    if (bestDist <= cfg.returnRadius) return null;

    if (cfg.excuseWhileMoving && _movingThroughReturn(context, punch, cfg)) {
      return null; // stepped out through the return — in-and-out, not a drop
    }

    // It didn't get back to guard — figure out how it failed for the cue.
    final endFrame =
        seq.frames[punch.endIndex < seq.length ? punch.endIndex : seq.length - 1];
    final wrist = geo.framePoint(endFrame, punch.side.wrist);
    final shoulder = geo.framePoint(endFrame, punch.side.shoulder);

    var mode = 'slow';
    if (!wrist.any((v) => v.isNaN)) {
      // Ended below where it launched from -> dropped.
      if (wrist[1] > ref[1] + cfg.dropMargin) {
        mode = 'dropped';
      } else if (!shoulder.any((v) => v.isNaN) &&
          geo.distance(wrist, shoulder) / scale > cfg.extendedReach) {
        mode = 'extended';
      }
    }

    // A truncated return window (the clip ended before the hand could come back)
    // can't tell a slow/extended return from simply running out of frames — only
    // a positively-observed drop survives it.
    final windowTruncated = seq.frames.last.timestampMs < deadline;
    if (cfg.requireFullReturnWindow && windowTruncated && mode != 'dropped') {
      return null;
    }

    return (mode, worstFrame);
  }

  /// The allowed return time for this punch, scaled to its throw speed (the
  /// extension phase start->peak), clamped to [returnWindowMs, maxReturnWindowMs].
  static double _returnWindowMs(
    PoseSequence seq,
    PunchEvent punch,
    GuardReturnConfig cfg,
  ) {
    final extensionMs = seq.frames[punch.peakIndex].timestampMs -
        seq.frames[punch.startIndex].timestampMs;
    final scaled = extensionMs * cfg.returnSpeedFactor;
    return scaled.clamp(cfg.returnWindowMs, cfg.maxReturnWindowMs).toDouble();
  }

  bool _movingThroughReturn(
    AnalysisContext context,
    PunchEvent punch,
    GuardReturnConfig cfg,
  ) {
    final seq = context.sequence;
    final speeds = context.stanceSpeed;
    final deadline =
        seq.frames[punch.endIndex].timestampMs + _returnWindowMs(seq, punch, cfg);
    for (var i = punch.peakIndex; i < seq.length; i++) {
      if (seq.frames[i].timestampMs > deadline) break;
      if (speeds[i] > cfg.movingSpeed) return true; // NaN > x is false = unknown
    }
    return false;
  }

  static String _coachingText(Stance stance, Side side, String failureMode) {
    final hand = side == stance.lead ? 'lead' : 'rear';
    if (failureMode == 'dropped') {
      return 'Your $hand hand drops after the punch — bring it back up to your '
          "guard, don't let it sink.";
    }
    if (failureMode == 'extended') {
      return "You're leaving the $hand hand hanging out there after the punch. "
          'Snap it back to guard every time.';
    }
    return 'Your $hand hand is slow getting back to guard. The return should be '
        'as fast as the punch went out.';
  }
}
