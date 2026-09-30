import 'dart:convert';
import 'dart:io';

import 'package:boxing_coach/analysis/checkpoint_evaluation.dart';
import 'package:boxing_coach/analysis/checkpoints.dart';
import 'package:boxing_coach/analysis/combination.dart';
import 'package:boxing_coach/analysis/combination_analysis.dart';
import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/error_codes.dart';
import 'package:boxing_coach/analysis/features.dart';
import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/analysis/pose_only_adapter.dart';
import 'package:boxing_coach/analysis/punch.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/domain/round_clip.dart';
import 'package:boxing_coach/domain/session_phase.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_support.dart';

void main() {
  group('catalogue', () {
    test('a 1-2-3 drill looks for exactly the coach\'s checkpoints', () {
      final ids = Checkpoints.forSequence(<int>[1, 2, 3]).map((c) => c.id);
      expect(ids, <String>[
        // Jab
        'jab_snap_back',
        // Cross
        'cross_full_rotation',
        'cross_shoulder_height',
        'cross_lead_hand_home',
        'cross_elbows_in',
        // Lead hook
        'lead_hook_level',
        'lead_hook_arm_90',
        'lead_hook_rotation',
        'lead_hook_rear_hand_home',
      ]);
    });

    test('a repeated punch is graded once', () {
      expect(Checkpoints.forSequence(<int>[1, 1, 2]).where((c) => c.punchNumber == 1),
          hasLength(1));
    });

    test('every checkpoint maps to a known fault code', () {
      const known = <String>{
        FaultCode.recSlow,
        FaultCode.rotInsufficient,
        FaultCode.punchBelowShoulder,
        FaultCode.guardLeadDropsDuringRear,
        FaultCode.guardRearDropsDuringLead,
        FaultCode.guardElbowsOut,
        FaultCode.punchHookNotLevel,
        FaultCode.punchHookArmAngle,
        FaultCode.guardLeadHandLow,
        FaultCode.guardRearHandLow,
      };
      for (var n = 1; n <= 6; n++) {
        for (final c in Checkpoints.forPunch(n)) {
          expect(known, contains(c.faultCode), reason: c.id);
        }
      }
    });
  });

  group('on-device grading', () {
    const scale = 0.20;
    const stance = Stance.orthodox;
    List<DrillCheckpoint> only(int number, String id) =>
        Checkpoints.forSequence(<int>[number]).where((c) => c.id == id).toList();

    CheckpointResult gradeOne(
      PoseSequence seq,
      PunchEvent punch,
      int number,
      String id,
    ) =>
        evaluateCheckpoints(seq, <PunchEvent>[punch], stance, scale, only(number, id))
            .single;

    test('jab snap-back: passes a quick return, fails a lingering jab', () {
      final seq = _frames(20, (_) => _neutral());
      final quick = gradeOne(
        seq,
        _punch(PunchType.straight, Side.left, start: 2, peak: 3, end: 4),
        1,
        'jab_snap_back',
      );
      expect(quick.status, CheckpointStatus.passed);

      final lingering = gradeOne(
        seq,
        _punch(PunchType.straight, Side.left, start: 2, peak: 3, end: 9),
        1,
        'jab_snap_back',
      );
      expect(lingering.status, CheckpointStatus.failed);
      expect(lingering.metrics['retract_ratio'], closeTo(6, 1e-9));
    });

    test('cross height: at the shoulder passes, well below fails', () {
      final cross = _punch(PunchType.straight, Side.right, start: 2, peak: 3, end: 4);
      final level = _frames(10, (_) => _neutral(rightWrist: const Keypoint(0.30, 0.40)));
      expect(gradeOne(level, cross, 2, 'cross_shoulder_height').status,
          CheckpointStatus.passed);
      final low = _frames(10, (_) => _neutral(rightWrist: const Keypoint(0.30, 0.52)));
      expect(gradeOne(low, cross, 2, 'cross_shoulder_height').status,
          CheckpointStatus.failed);
    });

    test('lead hand home on the cross: by the face passes, at the chest fails',
        () {
      final cross = _punch(PunchType.straight, Side.right, start: 2, peak: 3, end: 4);
      final home = _frames(
        10,
        (_) => _neutral(leftWrist: const Keypoint(0.46, 0.34), withNose: true),
      );
      expect(gradeOne(home, cross, 2, 'cross_lead_hand_home').status,
          CheckpointStatus.passed);
      final chest = _frames(
        10,
        (_) => _neutral(leftWrist: const Keypoint(0.44, 0.55), withNose: true),
      );
      expect(gradeOne(chest, cross, 2, 'cross_lead_hand_home').status,
          CheckpointStatus.failed);
    });

    test('hook level: at shoulder height passes; low or chopping down fails', () {
      final hook = _punch(PunchType.hook, Side.left, start: 2, peak: 3, end: 4);
      final level = _frames(
        10,
        (_) => _neutral(
          leftWrist: const Keypoint(0.30, 0.40),
          leftElbow: const Keypoint(0.30, 0.42),
        ),
      );
      expect(gradeOne(level, hook, 3, 'lead_hook_level').status,
          CheckpointStatus.passed);
      final low = _frames(
        10,
        (_) => _neutral(
          leftWrist: const Keypoint(0.30, 0.52),
          leftElbow: const Keypoint(0.32, 0.48),
        ),
      );
      expect(gradeOne(low, hook, 3, 'lead_hook_level').status,
          CheckpointStatus.failed);
      final chopping = _frames(
        10,
        (_) => _neutral(
          leftWrist: const Keypoint(0.30, 0.44),
          leftElbow: const Keypoint(0.34, 0.32),
        ),
      );
      expect(gradeOne(chopping, hook, 3, 'lead_hook_level').status,
          CheckpointStatus.failed);
    });

    test('hook arm angle: ~90° passes, a straight arm fails', () {
      final hook = _punch(PunchType.hook, Side.left, start: 2, peak: 3, end: 4);
      final bent = _frames(
        10,
        (_) => _neutral(
          leftElbow: const Keypoint(0.30, 0.40),
          leftWrist: const Keypoint(0.30, 0.28),
        ),
      );
      final r = gradeOne(bent, hook, 3, 'lead_hook_arm_90');
      expect(r.status, CheckpointStatus.passed);
      expect(r.metrics['elbow_deg'], closeTo(90, 0.5));

      final straight = _frames(
        10,
        (_) => _neutral(
          leftElbow: const Keypoint(0.30, 0.40),
          leftWrist: const Keypoint(0.18, 0.40),
        ),
      );
      expect(gradeOne(straight, hook, 3, 'lead_hook_arm_90').status,
          CheckpointStatus.failed);
    });

    test('rotation: shoulder turning through passes, squared up fails', () {
      final cross = _punch(PunchType.straight, Side.right, start: 2, peak: 3, end: 4);
      final turned = _frames(
        10,
        (i) => _neutral(
          rightShoulder: i >= 3 ? const Keypoint(0.51, 0.40) : null,
        ),
      );
      expect(gradeOne(turned, cross, 2, 'cross_full_rotation').status,
          CheckpointStatus.passed);
      final squared = _frames(10, (_) => _neutral());
      expect(gradeOne(squared, cross, 2, 'cross_full_rotation').status,
          CheckpointStatus.failed);
    });

    test('video-only checkpoints and missing landmarks are unmeasured, not '
        'guessed', () {
      final cross = _punch(PunchType.straight, Side.right, start: 2, peak: 3, end: 4);
      final seq = _frames(10, (_) => _neutral());
      expect(gradeOne(seq, cross, 2, 'cross_elbows_in').status,
          CheckpointStatus.unmeasured);
      final hook = _punch(PunchType.hook, Side.left, start: 2, peak: 3, end: 4);
      // No elbow in the neutral frame → no arm angle.
      expect(gradeOne(seq, hook, 3, 'lead_hook_arm_90').status,
          CheckpointStatus.unmeasured);
    });

    test('only punches the drill covers are graded; tallies roll up per '
        'checkpoint', () {
      final seq = _frames(30, (_) => _neutral());
      final punches = <PunchEvent>[
        _punch(PunchType.straight, Side.left, start: 2, peak: 3, end: 4),
        _punch(PunchType.straight, Side.left, start: 8, peak: 9, end: 16),
        _punch(PunchType.hook, Side.left, start: 20, peak: 21, end: 22),
        _punch(PunchType.unknown, Side.left, start: 24, peak: 25, end: 26),
      ];
      final checkpoints = Checkpoints.forSequence(<int>[1]);
      final results =
          evaluateCheckpoints(seq, punches, stance, scale, checkpoints);
      expect(results, hasLength(2)); // the two jabs only
      final tally = tallyCheckpoints(checkpoints, results).single;
      expect(tally.passed, 1);
      expect(tally.failed, 1);
      expect(tally.passRate, 0.5);
      expect(tally.firstFailureMs, 900);
    });
  });

  group('combination score', () {
    test('a failed checkpoint costs 1.5× and replaces the general issue', () {
      final seq = _frames(20, (i) => _neutral());
      final punches = <PunchEvent>[
        _punch(PunchType.straight, Side.left, start: 2, peak: 3, end: 4),
        _punch(PunchType.straight, Side.right, start: 8, peak: 9, end: 10),
      ];
      final combo = detectCombinations(seq, punches, Stance.orthodox).single;
      final failed = CheckpointResult(
        checkpointId: 'cross_lead_hand_home',
        punchNumber: 2,
        punchIndex: 1,
        status: CheckpointStatus.failed,
        timestampMs: 900,
        confidence: 0.7,
      );

      final result = analyzeCombination(
        seq,
        punches,
        combo,
        Stance.orthodox,
        0.2,
        checkpointResults: <CheckpointResult>[failed],
      );

      final issue = result.issues.single;
      expect(issue.checkpointId, 'cross_lead_hand_home');
      expect(issue.code, FaultCode.guardLeadDropsDuringRear);
      expect(result.score, 100 - 23); // moderate 15 × 1.5
      expect(
        CombinationIssue.fromJson(issue.toJson()).checkpointId,
        'cross_lead_hand_home',
      );
    });
  });

  group('PoseOnlyAdapter on a drill', () {
    final goldenDir = locateGoldenDir();
    if (goldenDir == null) {
      test('golden fixtures present', () => fail('run emit_golden_fixtures.py'));
      return;
    }
    PoseSequence fixture(String name) => PoseSequence.fromJson(
          jsonDecode(File('${goldenDir.path}/$name/input.json').readAsStringSync())
              as Map<String, Object?>,
        );

    test('a lingering jab in a jab drill is the first correction', () {
      final analysis = PoseOnlyAdapter().analyse(
        fixture('dropped_guard_jab'),
        const DrillContext(targetSequence: <int>[1]),
      );
      final tally = analysis.checkpointTallies.single;
      expect(tally.checkpoint.id, 'jab_snap_back');
      expect(tally.failed, 1);
      expect(analysis.correctionPriorities.first.description,
          startsWith(Checkpoints.jabSnapBack.failCue));
      final checkpointObs = analysis.specificObservations
          .where((o) => o.ruleId == PoseOnlyAdapter.checkpointRuleId);
      expect(checkpointObs.single.code, FaultCode.recSlow);
      expect(checkpointObs.single.severity, Severity.major); // 1 of 1 reps
      expect(analysis.overallSummary, contains('lingering'));
    });

    test('a clean jab passes the jab drill', () {
      final analysis = PoseOnlyAdapter().analyse(
        fixture('clean_jab'),
        const DrillContext(targetSequence: <int>[1]),
      );
      expect(analysis.checkpointTallies.single.passed, 1);
      expect(
        analysis.specificObservations
            .where((o) => o.ruleId == PoseOnlyAdapter.checkpointRuleId),
        isEmpty,
      );
    });

    test('a squared-up cross fails the rotation checkpoint, which replaces '
        'the general rotation fault', () {
      final analysis = PoseOnlyAdapter().analyse(
        fixture('squared_cross'),
        const DrillContext(targetSequence: <int>[1, 2]),
      );
      final rotation = analysis.checkpointTallies
          .firstWhere((t) => t.checkpoint.id == 'cross_full_rotation');
      expect(rotation.failed, 1);
      final rotationFaults = analysis.specificObservations
          .where((o) => o.code == FaultCode.rotInsufficient && o.severity.isFault);
      expect(rotationFaults.single.ruleId, PoseOnlyAdapter.checkpointRuleId);
    });

    test('a rotated cross passes it', () {
      final analysis = PoseOnlyAdapter().analyse(
        fixture('rotated_cross'),
        const DrillContext(targetSequence: <int>[2]),
      );
      final rotation = analysis.checkpointTallies
          .firstWhere((t) => t.checkpoint.id == 'cross_full_rotation');
      expect(rotation.passed, 1);
    });

    test('free work (no target) is unchanged', () {
      final seq = fixture('squared_cross');
      final free = PoseOnlyAdapter().analyse(seq, const DrillContext());
      expect(free.checkpointTallies, isEmpty);
      expect(
        free.specificObservations
            .where((o) => o.ruleId == PoseOnlyAdapter.checkpointRuleId),
        isEmpty,
      );
    });

    test('tallies survive the round trip to storage', () {
      final analysis = PoseOnlyAdapter().analyse(
        fixture('dropped_guard_jab'),
        const DrillContext(targetSequence: <int>[1]),
      );
      final back = RoundAnalysis.fromJson(
        jsonDecode(jsonEncode(analysis.toJson())) as Map<String, Object?>,
      );
      expect(back.checkpointTallies.single.checkpoint.id, 'jab_snap_back');
      expect(back.checkpointTallies.single.failed, 1);
    });
  });
  test('a clip keeps its drill target through storage', () {
    final clip = RoundClip(
      sessionId: 'drill_1',
      segmentIndex: 0,
      phase: SessionPhase.technical,
      path: '/clips/drill_1_seg0.mp4',
      recordedAt: DateTime(2026, 9, 30),
      targetSequence: const <int>[1, 2, 3],
    );
    final back = RoundClip.fromJson(
      jsonDecode(jsonEncode(clip.toJson())) as Map<String, Object?>,
    )!;
    expect(back.targetSequence, <int>[1, 2, 3]);
    expect(back.copyWith(durationMs: 5).targetSequence, <int>[1, 2, 3]);
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

/// A neutral full-body guard frame (torso length 0.20).
Map<Landmark, Keypoint> _neutral({
  Keypoint? leftWrist,
  Keypoint? rightWrist,
  Keypoint? leftElbow,
  Keypoint? rightShoulder,
  bool withNose = false,
}) => <Landmark, Keypoint>{
  if (withNose) Landmark.nose: const Keypoint(0.50, 0.30),
  Landmark.leftShoulder: const Keypoint(0.42, 0.40),
  Landmark.rightShoulder: rightShoulder ?? const Keypoint(0.58, 0.40),
  Landmark.leftHip: const Keypoint(0.44, 0.60),
  Landmark.rightHip: const Keypoint(0.56, 0.60),
  Landmark.leftAnkle: const Keypoint(0.44, 0.90),
  Landmark.rightAnkle: const Keypoint(0.56, 0.90),
  Landmark.leftWrist: leftWrist ?? const Keypoint(0.44, 0.42),
  Landmark.rightWrist: rightWrist ?? const Keypoint(0.56, 0.42),
  Landmark.leftElbow: ?leftElbow,
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
