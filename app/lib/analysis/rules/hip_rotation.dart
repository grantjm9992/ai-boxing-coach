import 'dart:math' as math;

import '../context.dart';
import '../geometry.dart' as geo;
import '../landmarks.dart';
import '../punch.dart';
import '../round_analysis.dart';
import '../rule.dart';

/// Rule: is the rear hand punched with rotation, or arm-only? Mirror of
/// `src/boxing_coach/analysis/rules/hip_rotation.py`.
///
/// A cross should be driven by hip/shoulder rotation — the rear shoulder comes
/// forward. We take the larger of the in-plane swing (x/y, a side camera) and
/// the depth drive (z, a front camera), relative to the hip centre so a step
/// isn't mistaken for rotation. Least certain of the rules: z is only estimated.
class HipRotationConfig {
  const HipRotationConfig({
    this.minShoulderDrive = 0.12,
    this.minPeakReach = 0.9,
  });

  final double minShoulderDrive;
  final double minPeakReach;
}

class HipRotationRule extends Rule {
  HipRotationRule([HipRotationConfig? config])
    : _cfg = config ?? const HipRotationConfig();

  final HipRotationConfig _cfg;

  @override
  String get id => 'hip_rotation';

  @override
  Set<String> get focusTags =>
      const <String>{'straight', 'power', 'combinations'};

  @override
  List<Observation> evaluate(AnalysisContext context) {
    final cfg = context.styleProfile.configFor(id, _cfg);
    final rear = context.drill.stance.rear;
    final seq = context.sequence;
    final observations = <Observation>[];

    for (final punch in context.punchesBy(rear)) {
      // Only the rear straight is driven by rotation this way.
      if (punch.punchType != PunchType.straight) continue;
      if (punch.peakReach < cfg.minPeakReach) continue;
      final drive = _shoulderDrive(context, rear, punch.startIndex, punch.peakIndex);
      if (drive == null) continue;
      if (drive < cfg.minShoulderDrive) {
        observations.add(
          Observation(
            ruleId: id,
            category: SkillCategory.straight,
            severity: Severity.moderate,
            coachingText:
                "You're squared up on the rear straight — punching with the arm. "
                'Turn the hip and shoulder over; let the rotation drive the shot.',
            timestampMs: punch.peakTimestampMs(seq),
            metrics: <String, double>{'shoulder_drive': drive},
            highlightLandmarks: <Landmark>[rear.shoulder],
          ),
        );
      }
    }
    return observations;
  }

  /// Rear-shoulder travel relative to the hips (torso-lengths): the max of the
  /// in-plane swing and the depth drive. Null if neither axis is measurable.
  double? _shoulderDrive(
    AnalysisContext context,
    Side side,
    int startIndex,
    int peakIndex,
  ) {
    final seq = context.sequence;
    final scale = context.bodyScale;
    final startF = seq.frames[startIndex];
    final peakF = seq.frames[peakIndex];

    final s0 = geo.framePoint(startF, side.shoulder);
    final s1 = geo.framePoint(peakF, side.shoulder);
    final h0 = geo.hipCenter(startF);
    final h1 = geo.hipCenter(peakF);
    var inplane = double.nan;
    final anyNan = <List<double>>[s0, s1, h0, h1].any((p) => p.any((v) => v.isNaN));
    if (!anyNan) {
      // distance(s1 - h1, s0 - h0) / scale
      final v1 = <double>[s1[0] - h1[0], s1[1] - h1[1]];
      final v0 = <double>[s0[0] - h0[0], s0[1] - h0[1]];
      inplane = geo.distance(v1, v0) / scale;
    }

    // Depth drive (front camera): MediaPipe z toward the lens.
    final z0 = startF.get(side.shoulder)?.z ?? double.nan;
    final z1 = peakF.get(side.shoulder)?.z ?? double.nan;
    final depth =
        (z0.isNaN || z1.isNaN) ? double.nan : (z1 - z0).abs() / scale;

    final drives = <double>[
      if (!inplane.isNaN) inplane,
      if (!depth.isNaN) depth,
    ];
    return drives.isEmpty ? null : drives.reduce(math.max);
  }
}
