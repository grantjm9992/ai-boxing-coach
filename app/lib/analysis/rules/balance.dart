import '../context.dart';
import '../error_codes.dart';
import '../geometry.dart' as geo;
import '../landmarks.dart';
import '../round_analysis.dart';
import '../rule.dart';

/// Rule: does the boxer stay balanced over the base after punching? (Brief §11.7.)
///
/// Balance in a single 2D view reads most reliably as the horizontal position of
/// the hips (centre of mass, roughly) relative to the base of support (the span
/// between the ankles). When the hips travel outside the feet after a punch, the
/// boxer is falling in behind the shot — off balance, and a beat late to counter.
///
/// We look only at the recovery window after each punch's peak: everyone's mass
/// shifts *during* extension; what matters is whether it comes back over the base.
class BalanceConfig {
  const BalanceConfig({
    this.maxHipOffset = 0.55,
    this.recoveryMarginFrames = 6,
    this.minFaultFraction = 0.4,
    this.confidence = 0.7,
  });

  /// Max hip-centre horizontal offset from the ankle centre, in torso-lengths,
  /// tolerated in the recovery window. Beyond this the hips are outside the base.
  final double maxHipOffset;

  /// Frames after a punch's end to keep watching the recovery.
  final int recoveryMarginFrames;

  /// Fraction of punches that must go off-balance before the round is flagged.
  final double minFaultFraction;

  final double confidence;
}

class BalanceRule extends Rule {
  BalanceRule([BalanceConfig? config]) : _cfg = config ?? const BalanceConfig();

  final BalanceConfig _cfg;

  @override
  String get id => 'balance';

  @override
  Set<String> get focusTags =>
      const <String>{'balance', 'footwork', 'movement'};

  @override
  List<Observation> evaluate(AnalysisContext context) {
    final cfg = context.styleProfile.configFor(id, _cfg);
    final seq = context.sequence;
    final scale = context.bodyScale;
    final punches = context.punches;
    if (punches.isEmpty || scale <= 0) return <Observation>[];

    var offBalance = 0;
    var assessed = 0;
    double worstOffset = 0;
    double? worstMs;

    for (final punch in punches) {
      final from = punch.peakIndex;
      final to =
          (punch.endIndex + cfg.recoveryMarginFrames).clamp(0, seq.frames.length - 1);
      double maxOffset = 0;
      double? maxMs;
      var sampled = false;
      for (var i = from; i <= to; i++) {
        final frame = seq.frames[i];
        final hips = geo.hipCenter(frame);
        final ankles = geo.ankleCenter(frame);
        if (hips.any((v) => v.isNaN) || ankles.any((v) => v.isNaN)) continue;
        sampled = true;
        final offset = (hips[0] - ankles[0]).abs() / scale;
        if (offset > maxOffset) {
          maxOffset = offset;
          maxMs = frame.timestampMs;
        }
      }
      if (!sampled) continue;
      assessed++;
      if (maxOffset > cfg.maxHipOffset) {
        offBalance++;
        if (maxOffset > worstOffset) {
          worstOffset = maxOffset;
          worstMs = maxMs;
        }
      }
    }

    if (assessed == 0) return <Observation>[];
    final fraction = offBalance / assessed;
    if (fraction < cfg.minFaultFraction) return <Observation>[];

    return <Observation>[
      Observation(
        ruleId: id,
        code: FaultCode.balOffAfterPunch,
        category: SkillCategory.footwork,
        severity: fraction >= 0.7 ? Severity.moderate : Severity.minor,
        confidence: cfg.confidence,
        coachingText:
            'Your hips drift out past your feet when you punch — you lose your '
            'base and end up leaning instead of centred. Punch from a stable '
            'stance and bring your weight back over your feet after each shot.',
        timestampMs: worstMs,
        metrics: <String, double>{
          'off_balance_fraction': fraction,
          'worst_hip_offset': worstOffset,
        },
        highlightLandmarks: const <Landmark>[Landmark.leftHip, Landmark.rightHip],
      ),
    ];
  }
}
