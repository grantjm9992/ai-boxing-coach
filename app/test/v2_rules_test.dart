import 'package:boxing_coach/analysis/context.dart';
import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/error_codes.dart';
import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/analysis/rules/balance.dart';
import 'package:boxing_coach/analysis/rules/body_lean.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 2 (brief §11.1, §11.7): the two frontal-honest V2 analyzers.
///
/// Both rules read a single frontal view, so the fixtures are synthetic
/// landmark sequences in image-normalised coordinates (x right, y down).
void main() {
  group('BodyLeanRule', () {
    test('flags a torso held tilted off-vertical', () {
      // Shoulders sit ~0.073 to the right of the hips over a 0.20 torso → ~20°.
      final seq = _sequence(
        frameCount: 35,
        stepMs: 100,
        build: (i) => _frame(shoulderCentreX: 0.573),
      );
      final obs = BodyLeanRule().evaluate(_context(seq));
      expect(obs, hasLength(1));
      expect(obs.single.code, FaultCode.leanRight);
      expect(obs.single.confidence, lessThan(1.0));
      expect(obs.single.metrics['median_tilt_deg'], greaterThan(12));
    });

    test('stays silent on an upright torso', () {
      final seq = _sequence(
        frameCount: 35,
        stepMs: 100,
        build: (i) => _frame(), // shoulders stacked over hips
      );
      expect(BodyLeanRule().evaluate(_context(seq)), isEmpty);
    });

    test('needs enough footage to judge posture', () {
      final seq = _sequence(
        frameCount: 5,
        stepMs: 100, // 400ms < minDurationMs
        build: (i) => _frame(shoulderCentreX: 0.573),
      );
      expect(BodyLeanRule().evaluate(_context(seq)), isEmpty);
    });
  });

  group('BalanceRule', () {
    test('flags hips drifting past the base after a punch', () {
      final seq = _punchSequence(hipCentreXInRecovery: 0.66);
      final obs = BalanceRule().evaluate(_context(seq));
      expect(obs, hasLength(1));
      expect(obs.single.code, FaultCode.balOffAfterPunch);
      expect(obs.single.metrics['worst_hip_offset'], greaterThan(0.55));
    });

    test('stays silent when the boxer recovers over the base', () {
      final seq = _punchSequence(hipCentreXInRecovery: 0.50);
      expect(BalanceRule().evaluate(_context(seq)), isEmpty);
    });

    test('no punches, nothing to judge', () {
      final seq = _sequence(
        frameCount: 20,
        stepMs: 100,
        build: (i) => _frame(),
      );
      expect(BalanceRule().evaluate(_context(seq)), isEmpty);
    });
  });
}

AnalysisContext _context(PoseSequence seq) =>
    AnalysisContext(sequence: seq, drill: const DrillContext());

PoseSequence _sequence({
  required int frameCount,
  required double stepMs,
  required PoseFrame Function(int i) build,
}) {
  return PoseSequence(
    frames: <PoseFrame>[
      for (var i = 0; i < frameCount; i++)
        PoseFrame(
          index: i,
          timestampMs: i * stepMs,
          keypoints: build(i).keypoints,
        ),
    ],
    fps: 1000 / stepMs,
  );
}

/// A guard → lead-hand extension → retraction sequence with the hips optionally
/// shifted off the base during recovery.
PoseSequence _punchSequence({required double hipCentreXInRecovery}) {
  // 0-9 guard, 10-13 extend, 14-24 recover.
  PoseFrame at(int i) {
    double leadWristX;
    double hipCentreX;
    if (i < 10) {
      leadWristX = 0.44; // guard, near lead shoulder
      hipCentreX = 0.50;
    } else if (i < 14) {
      final t = (i - 10) / 3.0; // 0..1 extension
      leadWristX = 0.44 - 0.20 * t; // reach out to the left
      hipCentreX = 0.50;
    } else {
      final t = (i - 14) / 4.0; // retract over ~4 frames
      leadWristX = (0.24 + 0.20 * t).clamp(0.24, 0.44);
      hipCentreX = hipCentreXInRecovery;
    }
    return _frame(hipCentreX: hipCentreX, leadWristX: leadWristX);
  }

  return _sequence(frameCount: 25, stepMs: 100, build: at);
}

/// One full-body frontal frame. Shoulders and ankles are fixed; the hip centre
/// and the lead (left) wrist are the levers the tests move.
PoseFrame _frame({
  double shoulderCentreX = 0.50,
  double hipCentreX = 0.50,
  double? leadWristX,
}) {
  const shoulderY = 0.40;
  const hipY = 0.60;
  const ankleY = 0.90;
  final lwx = leadWristX ?? 0.44;
  return PoseFrame(
    index: 0,
    timestampMs: 0,
    keypoints: <Landmark, Keypoint>{
      Landmark.leftShoulder: Keypoint(shoulderCentreX - 0.08, shoulderY),
      Landmark.rightShoulder: Keypoint(shoulderCentreX + 0.08, shoulderY),
      Landmark.leftHip: Keypoint(hipCentreX - 0.06, hipY),
      Landmark.rightHip: Keypoint(hipCentreX + 0.06, hipY),
      Landmark.leftAnkle: const Keypoint(0.44, ankleY),
      Landmark.rightAnkle: const Keypoint(0.56, ankleY),
      // Lead (left) wrist + elbow move; rear (right) wrist stays in guard.
      Landmark.leftWrist: Keypoint(lwx, 0.44),
      Landmark.leftElbow: Keypoint((lwx + shoulderCentreX - 0.08) / 2, 0.42),
      Landmark.rightWrist: Keypoint(shoulderCentreX + 0.06, 0.44),
    },
  );
}
