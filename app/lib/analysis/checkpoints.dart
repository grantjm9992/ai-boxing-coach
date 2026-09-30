import 'error_codes.dart';
import 'landmarks.dart';
import 'punch.dart';

/// Technique checkpoints — the specific things a combination or technical
/// drill is looking for, punch by punch.
///
/// A drill of 1-2-3 isn't judged like free shadow boxing: the jab must snap
/// back, the cross must rotate fully at shoulder height with the lead hand
/// home, the hook must be level with the arm at 90°. Each of those is a
/// [TechniqueCheckpoint]. They are defined per punch number, so any combination
/// is simply the checkpoints of its punches in order, and they carry more
/// weight than general faults wherever a drill is analysed: the on-device
/// combination score, the round's corrections, and the AI review.

/// How the on-device engine verifies a checkpoint from pose, if it can.
enum CheckpointCheck {
  /// The punching hand comes back at least about as fast as it went out.
  snapBack,

  /// Hips and shoulders turn through the punch (shoulder travel vs the hips).
  rotation,

  /// The punch lands at shoulder height or above.
  punchAtShoulderHeight,

  /// The other hand is back at the face while this punch is out.
  guardHandAtFace,

  /// A hook travels level at shoulder height, not downward.
  hookLevel,

  /// A hook's arm is bent close to 90° at the point of impact.
  hookArmAngle,

  /// Not measurable from monocular pose — judged from the video by the AI.
  videoOnly,
}

/// One thing a drill is looking for on one punch.
class TechniqueCheckpoint {
  const TechniqueCheckpoint({
    required this.id,
    required this.label,
    required this.detail,
    required this.check,
    required this.faultCode,
    required this.failCue,
  });

  /// Stable identifier, e.g. `cross_lead_hand_home`. Keyed on by results, the
  /// AI's findings and analytics — don't repurpose an id.
  final String id;

  /// Short label for lists: "Lead hand back protecting the face".
  final String label;

  /// The full standard, for the drill screen and the AI.
  final String detail;

  /// How the on-device engine verifies it.
  final CheckpointCheck check;

  /// The taxonomy code a failure maps to (annotations/taxonomy/codes.json).
  final String faultCode;

  /// The coaching line when it fails, spoken in the coach's voice.
  final String failCue;

  /// Whether the on-device engine can grade this checkpoint at all.
  bool get measurable => check != CheckpointCheck.videoOnly;
}

/// A checkpoint in the context of a drill: which punch in the combination it
/// belongs to.
class DrillCheckpoint {
  const DrillCheckpoint({
    required this.checkpoint,
    required this.punchNumber,
    required this.punchName,
  });

  final TechniqueCheckpoint checkpoint;
  final int punchNumber;
  final String punchName;

  String get id => checkpoint.id;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': checkpoint.id,
    'punch': punchName,
    'label': checkpoint.label,
    'detail': checkpoint.detail,
    'code': checkpoint.faultCode,
    'measured_on_device': checkpoint.measurable,
  };
}

/// The checkpoint catalogue, by punch number (1 jab … 6 rear uppercut).
class Checkpoints {
  const Checkpoints._();

  // ------------------------------------------------------------------ 1 · jab
  static const jabSnapBack = TechniqueCheckpoint(
    id: 'jab_snap_back',
    label: 'Snaps back after extension',
    detail:
        'The jab comes straight back to the face after full extension — at '
        'least as fast as it went out, on the same line.',
    check: CheckpointCheck.snapBack,
    faultCode: FaultCode.recSlow,
    failCue: 'Your jab is lingering out there. Snap it straight back to your '
        'face as fast as it went out.',
  );

  // ---------------------------------------------------------------- 2 · cross
  static const crossFullRotation = TechniqueCheckpoint(
    id: 'cross_full_rotation',
    label: 'Full rotation',
    detail:
        'The rear hip and shoulder turn all the way through the cross, with '
        'the rear heel pivoting.',
    check: CheckpointCheck.rotation,
    faultCode: FaultCode.rotInsufficient,
    failCue: "You're arm-punching the cross. Turn the rear hip and shoulder all "
        'the way through and pivot the back heel.',
  );

  static const crossShoulderHeight = TechniqueCheckpoint(
    id: 'cross_shoulder_height',
    label: 'At shoulder height or higher',
    detail:
        'The cross lands at shoulder height or higher, so the rear shoulder '
        'rolls up and blocks any counter from that side.',
    check: CheckpointCheck.punchAtShoulderHeight,
    faultCode: FaultCode.punchBelowShoulder,
    failCue: 'Your cross is dropping below shoulder height. Keep it up so the '
        'shoulder rolls up and covers your chin.',
  );

  static const crossLeadHandHome = TechniqueCheckpoint(
    id: 'cross_lead_hand_home',
    label: 'Lead hand back protecting the face',
    detail:
        'While the cross is out, the lead hand has returned fully to protect '
        'the face.',
    check: CheckpointCheck.guardHandAtFace,
    faultCode: FaultCode.guardLeadDropsDuringRear,
    failCue: "Your lead hand isn't back at your face when the cross goes. "
        'Bring it all the way home before you throw the right.',
  );

  static const crossElbowsIn = TechniqueCheckpoint(
    id: 'cross_elbows_in',
    label: 'Elbows in',
    detail: 'Both elbows stay tucked in while the cross is thrown.',
    check: CheckpointCheck.videoOnly,
    faultCode: FaultCode.guardElbowsOut,
    failCue: 'Your elbows are flaring on the cross. Keep them tucked in to '
        'cover the body.',
  );

  // ------------------------------------------------------------ 3 · lead hook
  static const leadHookLevel = TechniqueCheckpoint(
    id: 'lead_hook_level',
    label: 'Level at shoulder height, not downward',
    detail:
        'The lead hook is thrown horizontally at shoulder height — not '
        'chopping downward.',
    check: CheckpointCheck.hookLevel,
    faultCode: FaultCode.punchHookNotLevel,
    failCue: 'Your hook is chopping downward. Bring it across level, at '
        'shoulder height.',
  );

  static const leadHookArm90 = TechniqueCheckpoint(
    id: 'lead_hook_arm_90',
    label: 'Arm bent at about 90°',
    detail:
        'The arm is bent at about 90° through the hook, for maximum power.',
    check: CheckpointCheck.hookArmAngle,
    faultCode: FaultCode.punchHookArmAngle,
    failCue: 'Lock the hook at about 90° — too open and it turns into a '
        'swing, too closed and it has no reach.',
  );

  static const leadHookRotation = TechniqueCheckpoint(
    id: 'lead_hook_rotation',
    label: 'Full hip rotation',
    detail: 'The hips turn fully through the lead hook, lead foot pivoting.',
    check: CheckpointCheck.rotation,
    faultCode: FaultCode.rotInsufficient,
    failCue: 'The power in the hook comes from the hips. Turn them all the '
        'way through and pivot the lead foot.',
  );

  static const leadHookRearHandHome = TechniqueCheckpoint(
    id: 'lead_hook_rear_hand_home',
    label: 'Rear hand back defending the face',
    detail: 'While the lead hook is out, the rear hand has returned to defend '
        'the face.',
    check: CheckpointCheck.guardHandAtFace,
    faultCode: FaultCode.guardRearDropsDuringLead,
    failCue: "Your rear hand isn't back at your face when the hook goes. Get "
        'it home to defend.',
  );

  // ------------------------------------------------------------ 4 · rear hook
  static const rearHookLevel = TechniqueCheckpoint(
    id: 'rear_hook_level',
    label: 'Level at shoulder height, not downward',
    detail: 'The rear hook is thrown horizontally at shoulder height — not '
        'chopping downward.',
    check: CheckpointCheck.hookLevel,
    faultCode: FaultCode.punchHookNotLevel,
    failCue: 'Your rear hook is chopping downward. Bring it across level, at '
        'shoulder height.',
  );

  static const rearHookArm90 = TechniqueCheckpoint(
    id: 'rear_hook_arm_90',
    label: 'Arm bent at about 90°',
    detail: 'The arm is bent at about 90° through the rear hook.',
    check: CheckpointCheck.hookArmAngle,
    faultCode: FaultCode.punchHookArmAngle,
    failCue: 'Keep the rear hook at about 90° — don\'t let it open into a '
        'swing.',
  );

  static const rearHookRotation = TechniqueCheckpoint(
    id: 'rear_hook_rotation',
    label: 'Full hip rotation',
    detail: 'The hips turn fully through the rear hook, rear heel pivoting.',
    check: CheckpointCheck.rotation,
    faultCode: FaultCode.rotInsufficient,
    failCue: 'Turn the hips all the way through the rear hook and pivot the '
        'back heel.',
  );

  static const rearHookLeadHandHome = TechniqueCheckpoint(
    id: 'rear_hook_lead_hand_home',
    label: 'Lead hand back defending the face',
    detail: 'While the rear hook is out, the lead hand is back defending the '
        'face.',
    check: CheckpointCheck.guardHandAtFace,
    faultCode: FaultCode.guardLeadDropsDuringRear,
    failCue: "Your lead hand isn't home when the rear hook goes. Keep it at "
        'your face.',
  );

  // -------------------------------------------------------- 5 · lead uppercut
  static const leadUppercutLegDrive = TechniqueCheckpoint(
    id: 'lead_uppercut_leg_drive',
    label: 'Driven up from the legs, no wind-up',
    detail: 'A small dip and the lead uppercut drives up through the legs — '
        'the hand does not drop to wind up first.',
    check: CheckpointCheck.videoOnly,
    faultCode: FaultCode.guardLeadHandLow,
    failCue: "You're dropping the hand to wind up the uppercut. Dip with the "
        'legs and drive up from there instead.',
  );

  static const leadUppercutRearHandHome = TechniqueCheckpoint(
    id: 'lead_uppercut_rear_hand_home',
    label: 'Rear hand back defending the face',
    detail: 'While the lead uppercut is out, the rear hand defends the face.',
    check: CheckpointCheck.guardHandAtFace,
    faultCode: FaultCode.guardRearDropsDuringLead,
    failCue: 'Keep the rear hand at your face while the uppercut goes.',
  );

  // -------------------------------------------------------- 6 · rear uppercut
  static const rearUppercutLegDrive = TechniqueCheckpoint(
    id: 'rear_uppercut_leg_drive',
    label: 'Driven up from the legs and hips, no wind-up',
    detail: 'The rear uppercut drives up from the legs with the hips turning '
        '— the hand does not drop to wind up first.',
    check: CheckpointCheck.videoOnly,
    faultCode: FaultCode.guardRearHandLow,
    failCue: "You're dropping the rear hand to wind up. Dip, turn the hips "
        'and drive the uppercut up from the legs.',
  );

  static const rearUppercutLeadHandHome = TechniqueCheckpoint(
    id: 'rear_uppercut_lead_hand_home',
    label: 'Lead hand back defending the face',
    detail: 'While the rear uppercut is out, the lead hand defends the face.',
    check: CheckpointCheck.guardHandAtFace,
    faultCode: FaultCode.guardLeadDropsDuringRear,
    failCue: 'Keep the lead hand at your face while the rear uppercut goes.',
  );

  /// The checkpoints for one punch number, in the order a coach would call
  /// them. Empty for an unknown number.
  static List<TechniqueCheckpoint> forPunch(int number) => switch (number) {
    1 => const <TechniqueCheckpoint>[jabSnapBack],
    2 => const <TechniqueCheckpoint>[
      crossFullRotation,
      crossShoulderHeight,
      crossLeadHandHome,
      crossElbowsIn,
    ],
    3 => const <TechniqueCheckpoint>[
      leadHookLevel,
      leadHookArm90,
      leadHookRotation,
      leadHookRearHandHome,
    ],
    4 => const <TechniqueCheckpoint>[
      rearHookLevel,
      rearHookArm90,
      rearHookRotation,
      rearHookLeadHandHome,
    ],
    5 => const <TechniqueCheckpoint>[
      leadUppercutLegDrive,
      leadUppercutRearHandHome,
    ],
    6 => const <TechniqueCheckpoint>[
      rearUppercutLegDrive,
      rearUppercutLeadHandHome,
    ],
    _ => const <TechniqueCheckpoint>[],
  };

  /// A drill's checkpoints: each distinct punch in [sequence], in the order it
  /// first appears (a 1-1-2 grades the jab once, not twice).
  static List<DrillCheckpoint> forSequence(List<int> sequence) {
    final seen = <int>{};
    return <DrillCheckpoint>[
      for (final number in sequence)
        if (seen.add(number))
          for (final checkpoint in forPunch(number))
            DrillCheckpoint(
              checkpoint: checkpoint,
              punchNumber: number,
              punchName: punchLabel(number),
            ),
    ];
  }

  /// Display name for a punch number (the default numbering, brief §7).
  static String punchLabel(int number) => switch (number) {
    1 => 'Jab',
    2 => 'Cross',
    3 => 'Lead hook',
    4 => 'Rear hook',
    5 => 'Lead uppercut',
    6 => 'Rear uppercut',
    _ => 'Punch $number',
  };

  /// The motion class and hand a punch number means, for the evaluator.
  static ({PunchType type, bool isLead})? shapeOf(int number) => switch (number) {
    1 => (type: PunchType.straight, isLead: true),
    2 => (type: PunchType.straight, isLead: false),
    3 => (type: PunchType.hook, isLead: true),
    4 => (type: PunchType.hook, isLead: false),
    5 => (type: PunchType.uppercut, isLead: true),
    6 => (type: PunchType.uppercut, isLead: false),
    _ => null,
  };

  /// The side that throws punch [number] in [stance].
  static Side? sideOf(int number, Stance stance) {
    final shape = shapeOf(number);
    if (shape == null) return null;
    return shape.isLead ? stance.lead : stance.rear;
  }
}
