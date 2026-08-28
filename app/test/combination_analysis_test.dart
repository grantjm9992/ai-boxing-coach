import 'package:boxing_coach/analysis/combination.dart';
import 'package:boxing_coach/analysis/combination_analysis.dart';
import 'package:boxing_coach/analysis/error_codes.dart';
import 'package:boxing_coach/analysis/features.dart';
import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/analysis/punch.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 4 (brief §10): scoring how well a detected combination was executed.
///
/// A jab (left, peak@3) then cross (right, peak@9). The analyzer samples only a
/// few frames — the second punch's start (recovery of the first hand), each
/// punch's peak (the other hand's guard), and the tail (end balance) — so the
/// fixtures set exactly those.
void main() {
  const stance = Stance.orthodox;
  const scale = 0.20;

  // Jab: start 2, peak 3, end 4. Cross: start 8, peak 9, end 10.
  final punches = <PunchEvent>[
    _punch(PunchType.straight, Side.left, start: 2, peak: 3, end: 4),
    _punch(PunchType.straight, Side.right, start: 8, peak: 9, end: 10),
  ];
  final combo = detectCombinations(_frames(20, (_) => _neutral()), punches, stance)
      .single;

  test('clean execution scores 100 with no issues', () {
    final seq = _frames(20, (i) => _neutral());
    final result = analyzeCombination(seq, punches, combo, stance, scale);
    expect(result.issues, isEmpty);
    expect(result.score, 100);
  });

  test('dropped guard, no recovery and lost end-balance each cost points', () {
    final seq = _frames(20, (i) {
      if (i == 3) {
        // At the jab's peak the rear (right) guard hand is down at the waist.
        return _neutral(rightWrist: const Keypoint(0.56, 0.62));
      }
      if (i == 8) {
        // The jab hand is still extended when the cross starts — no recovery.
        return _neutral(leftWrist: const Keypoint(0.24, 0.42));
      }
      if (i >= 9) {
        // After the cross the hips fall out past the base.
        return _neutral(hipCentreX: 0.66);
      }
      return _neutral();
    });

    final result = analyzeCombination(seq, punches, combo, stance, scale);
    final codes = result.issues.map((e) => e.code).toSet();
    expect(codes, contains(FaultCode.recHandNotReturned));
    expect(codes, contains(FaultCode.guardRearDropsDuringLead));
    expect(codes, contains(FaultCode.balOffAfterCombination));
    expect(result.score, 100 - 3 * 15); // three moderate faults
    expect(result.metrics['worst_end_hip_offset'], greaterThan(0.55));
  });

  test('round-trips through JSON', () {
    final seq = _frames(20, (i) => _neutral());
    final result = analyzeCombination(seq, punches, combo, stance, scale);
    final back = CombinationAnalysis.fromJson(result.toJson());
    expect(back.score, result.score);
    expect(back.combination.sequence, result.combination.sequence);
    expect(back.issues.length, result.issues.length);
  });
}

PoseSequence _frames(int n, Map<Landmark, Keypoint> Function(int i) build) =>
    PoseSequence(
      frames: <PoseFrame>[
        for (var i = 0; i < n; i++)
          PoseFrame(index: i, timestampMs: i * 100.0, keypoints: build(i)),
      ],
      fps: 10,
    );

/// A neutral full-body guard frame; the levers are the two wrists and the hips.
Map<Landmark, Keypoint> _neutral({
  Keypoint? leftWrist,
  Keypoint? rightWrist,
  double hipCentreX = 0.50,
}) => <Landmark, Keypoint>{
  Landmark.leftShoulder: const Keypoint(0.42, 0.40),
  Landmark.rightShoulder: const Keypoint(0.58, 0.40),
  Landmark.leftHip: Keypoint(hipCentreX - 0.06, 0.60),
  Landmark.rightHip: Keypoint(hipCentreX + 0.06, 0.60),
  Landmark.leftAnkle: const Keypoint(0.44, 0.90),
  Landmark.rightAnkle: const Keypoint(0.56, 0.90),
  Landmark.leftWrist: leftWrist ?? const Keypoint(0.44, 0.42),
  Landmark.rightWrist: rightWrist ?? const Keypoint(0.56, 0.42),
};

PunchEvent _punch(
  PunchType type,
  Side side, {
  required int start,
  required int peak,
  required int end,
}) => PunchEvent(
  side: side,
  startIndex: start,
  peakIndex: peak,
  endIndex: end,
  peakReach: 1.0,
  punchType: type,
);
