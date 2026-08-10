import '../domain/exercise.dart';
import '../domain/session_phase.dart';
import '../domain/skill_category.dart';

/// The v0.1 exercise library.
///
/// Convention: each exercise's category weights sum to roughly 1.0, so a
/// three-minute round contributes three minutes of training load spread across
/// the categories it develops. That keeps the balance view honest — a round
/// cannot count three minutes towards four different categories.
///
/// Cues are deliberately short. The coach speaks them over a working athlete,
/// and the spec is explicit that the coach does not talk over you.
class ExerciseLibrary {
  const ExerciseLibrary._();

  static const List<Exercise> all = <Exercise>[
    ..._warmUp,
    ..._conditioning,
    ..._shadow,
    ..._technical,
    ..._coolDown,
  ];

  static final Map<String, Exercise> _byKey = <String, Exercise>{
    for (final exercise in all) exercise.key: exercise,
  };

  /// Throws if the key is unknown — a template referencing a missing exercise
  /// is a programming error, not a runtime condition to paper over.
  static Exercise byKey(String key) {
    final exercise = _byKey[key];
    if (exercise == null) {
      throw ArgumentError.value(key, 'key', 'Unknown exercise');
    }
    return exercise;
  }

  static bool contains(String key) => _byKey.containsKey(key);

  static List<Exercise> forPhase(SessionPhase phase) =>
      all.where((exercise) => exercise.phase == phase).toList();

  static List<Exercise> forCategory(SkillCategory category) =>
      all
          .where((exercise) => exercise.categoryWeights.containsKey(category))
          .toList()
        ..sort(
          (a, b) => (b.categoryWeights[category] ?? 0).compareTo(
            a.categoryWeights[category] ?? 0,
          ),
        );

  // ---------------------------------------------------------------- warm-up

  static const List<Exercise> _warmUp = <Exercise>[
    Exercise(
      key: 'joint_circles',
      label: 'Joint circles',
      description:
          'Neck, shoulders, elbows, wrists, hips, knees, ankles. '
          'Ten slow circles each, both directions.',
      phase: SessionPhase.warmUp,
      defaultDurationSeconds: 120,
      difficulty: 1,
      categoryWeights: <SkillCategory, double>{SkillCategory.mobility: 1.0},
      cues: <String>[
        'Slow circles. Full range, no forcing.',
        'Both directions on every joint.',
        'Wrists matter — you will be making fists for the next hour.',
      ],
    ),
    Exercise(
      key: 'arm_swings',
      label: 'Arm swings and shoulder openers',
      description:
          'Cross-body swings and big backward circles to open the '
          'shoulders and upper back.',
      phase: SessionPhase.warmUp,
      defaultDurationSeconds: 60,
      difficulty: 1,
      categoryWeights: <SkillCategory, double>{SkillCategory.mobility: 1.0},
      cues: <String>[
        'Big swings. Let the shoulder blades move.',
        'Stay tall — do not lean back into it.',
      ],
    ),
    Exercise(
      key: 'light_skipping',
      label: 'Light skipping',
      description: 'Easy rope or shadow-rope. Low bounce, relaxed shoulders.',
      phase: SessionPhase.warmUp,
      defaultDurationSeconds: 180,
      difficulty: 2,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.cardio: 0.7,
        SkillCategory.footwork: 0.3,
      },
      cues: <String>[
        'Low bounce. Stay on the balls of your feet.',
        'Shoulders down, elbows in. Let the wrists turn the rope.',
        'Breathe through your nose while it is still easy.',
      ],
    ),
    Exercise(
      key: 'jog_in_place',
      label: 'Jog on the spot',
      description: 'Light jog building to knee lifts and heel flicks.',
      phase: SessionPhase.warmUp,
      defaultDurationSeconds: 90,
      difficulty: 1,
      categoryWeights: <SkillCategory, double>{SkillCategory.cardio: 1.0},
      cues: <String>[
        'Light feet. Quick contacts with the floor.',
        'Bring the knees up for the last thirty seconds.',
      ],
    ),
    Exercise(
      key: 'jumping_jacks',
      label: 'Jumping jacks',
      description:
          'Full range, controlled tempo. Raises heart rate without '
          'loading anything.',
      phase: SessionPhase.warmUp,
      defaultDurationSeconds: 60,
      difficulty: 1,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.cardio: 0.8,
        SkillCategory.mobility: 0.2,
      },
      cues: <String>[
        'Hands all the way overhead.',
        'Soft knees on the landing.',
      ],
    ),
    Exercise(
      key: 'dynamic_stretch',
      label: 'Dynamic stretching',
      description: 'Leg swings, walking lunges with a twist, torso rotations.',
      phase: SessionPhase.warmUp,
      defaultDurationSeconds: 120,
      difficulty: 1,
      categoryWeights: <SkillCategory, double>{SkillCategory.mobility: 1.0},
      cues: <String>[
        'Moving stretches only. Save the long holds for the cool-down.',
        'Rotate through the mid-back — that is where punching power turns.',
      ],
    ),
    Exercise(
      key: 'hip_openers',
      label: 'Hip openers',
      description:
          'Leg swings front-to-back and across, hip circles, '
          'deep squat rocks.',
      phase: SessionPhase.warmUp,
      defaultDurationSeconds: 90,
      difficulty: 1,
      categoryWeights: <SkillCategory, double>{SkillCategory.mobility: 1.0},
      cues: <String>[
        'Hips do the work in every punch. Open them properly.',
        'Control the swing, do not throw the leg.',
      ],
    ),
    Exercise(
      key: 'stance_and_steps',
      label: 'Stance checks and steps',
      description:
          'Settle into stance, then step forward, back, left, right, '
          'returning to a clean guard each time.',
      phase: SessionPhase.warmUp,
      defaultDurationSeconds: 120,
      difficulty: 2,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.footwork: 0.8,
        SkillCategory.mobility: 0.2,
      },
      cues: <String>[
        'Feet shoulder width. Weight even. Knees soft.',
        'Step with the near foot first, the other follows.',
        'Never cross your feet.',
      ],
    ),
    Exercise(
      key: 'shadow_activation',
      label: 'Light shadow — movement only',
      description:
          'Boxing-specific activation. Move, feint, throw at maybe '
          'thirty percent. No power.',
      phase: SessionPhase.warmUp,
      defaultDurationSeconds: 150,
      difficulty: 2,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.footwork: 0.5,
        SkillCategory.rhythmTiming: 0.3,
        SkillCategory.mobility: 0.2,
      },
      cues: <String>[
        'Thirty percent. This is activation, not a round.',
        'Long and loose. Feel the shoulders warm up.',
        'Guard still comes back — even at this pace.',
      ],
    ),
  ];

  // ----------------------------------------------------------- conditioning

  static const List<Exercise> _conditioning = <Exercise>[
    Exercise(
      key: 'push_ups',
      label: 'Push-ups',
      description:
          'Steady tempo, full lockout, elbows tracking back rather '
          'than flaring.',
      phase: SessionPhase.conditioning,
      defaultDurationSeconds: 120,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.muscularEndurance: 0.8,
        SkillCategory.power: 0.2,
      },
      cues: <String>[
        'Elbows back, not out.',
        'Body in one line — no sagging hips.',
        'Breathe out on the way up.',
      ],
    ),
    Exercise(
      key: 'squat_jumps',
      label: 'Squat jumps',
      description: 'Explosive up, quiet down. Quality over count.',
      phase: SessionPhase.conditioning,
      defaultDurationSeconds: 120,
      difficulty: 4,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.power: 0.7,
        SkillCategory.muscularEndurance: 0.3,
      },
      cues: <String>[
        'Drive through the heels.',
        'Land soft. Absorb it through the knees.',
        'Chest up all the way through.',
      ],
    ),
    Exercise(
      key: 'burpees',
      label: 'Burpees',
      description:
          'The honest conditioning exercise. Steady pace beats a fast '
          'start every time.',
      phase: SessionPhase.conditioning,
      defaultDurationSeconds: 120,
      difficulty: 4,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.cardio: 0.6,
        SkillCategory.muscularEndurance: 0.4,
      },
      cues: <String>[
        'Find a pace you can hold. Do not sprint the first thirty.',
        'Chest to the floor if you can.',
        'Stand tall at the top.',
      ],
    ),
    Exercise(
      key: 'plank',
      label: 'Plank',
      description:
          'Braced, ribs down, glutes on. Boxing needs a trunk that '
          'transmits force.',
      phase: SessionPhase.conditioning,
      defaultDurationSeconds: 90,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.muscularEndurance: 1.0,
      },
      cues: <String>[
        'Ribs down, glutes squeezed.',
        'Do not let the hips drift up.',
        'Breathe. Holding your breath is not bracing.',
      ],
    ),
    Exercise(
      key: 'mountain_climbers',
      label: 'Mountain climbers',
      description: 'Fast knees, still shoulders.',
      phase: SessionPhase.conditioning,
      defaultDurationSeconds: 90,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.cardio: 0.6,
        SkillCategory.muscularEndurance: 0.4,
      },
      cues: <String>[
        'Shoulders stacked over the hands.',
        'Knees drive, hips stay low.',
      ],
    ),
    Exercise(
      key: 'skipping_intervals',
      label: 'Skipping intervals',
      description:
          'Thirty seconds hard, thirty seconds easy, repeated through '
          'the round.',
      phase: SessionPhase.conditioning,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.cardio: 0.8,
        SkillCategory.footwork: 0.2,
      },
      cues: <String>[
        'Pick the pace up — this is the hard thirty.',
        'Ease off. Keep the rope turning.',
        'Relaxed shoulders even when it burns.',
      ],
    ),
    Exercise(
      key: 'tempo_shadow',
      label: 'Tempo shadow',
      description:
          'Continuous shadow at a working heart rate. Volume, not '
          'power.',
      phase: SessionPhase.conditioning,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.cardio: 0.6,
        SkillCategory.combinations: 0.2,
        SkillCategory.rhythmTiming: 0.2,
      },
      cues: <String>[
        'Keep the punches coming. Volume over power.',
        'Breathe out on every shot.',
        'Do not stand still — move between combinations.',
      ],
    ),
    Exercise(
      key: 'footwork_in_out',
      label: 'In-and-out footwork drill',
      description:
          'Step in to range, step straight back out. Continuous, '
          'sharp, on the balls of the feet.',
      phase: SessionPhase.conditioning,
      defaultDurationSeconds: 150,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.footwork: 0.7,
        SkillCategory.distanceManagement: 0.3,
      },
      cues: <String>[
        'Push off the back foot going in.',
        'Straight back out — do not drift sideways by accident.',
        'Guard stays up the whole time.',
      ],
    ),
    Exercise(
      key: 'sprawl_and_shadow',
      label: 'Sprawl and shadow',
      description: 'Drop to a sprawl, back up, throw a combination. Repeat.',
      phase: SessionPhase.conditioning,
      defaultDurationSeconds: 150,
      difficulty: 4,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.cardio: 0.5,
        SkillCategory.muscularEndurance: 0.3,
        SkillCategory.combinations: 0.2,
      },
      cues: <String>[
        'Up sharp, straight into the combination.',
        'Reset your stance before you throw.',
      ],
    ),
    Exercise(
      key: 'hollow_hold',
      label: 'Hollow hold',
      description: 'Lower back pinned to the floor, arms and legs extended.',
      phase: SessionPhase.conditioning,
      defaultDurationSeconds: 60,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.muscularEndurance: 1.0,
      },
      cues: <String>[
        'Low back flat on the floor. That is the whole exercise.',
        'Bend the knees if the back lifts.',
      ],
    ),
    Exercise(
      key: 'med_ball_slams',
      label: 'Medicine ball slams',
      description:
          'Full-body extension then a hard slam. Trains the same '
          'chain as a cross.',
      phase: SessionPhase.conditioning,
      defaultDurationSeconds: 120,
      difficulty: 4,
      requiresEquipment: true,
      equipmentNotes: 'Medicine ball, 4-8 kg, non-bouncing.',
      categoryWeights: <SkillCategory, double>{
        SkillCategory.power: 0.8,
        SkillCategory.muscularEndurance: 0.2,
      },
      cues: <String>[
        'Full extension overhead before you slam.',
        'Slam through the floor, not at it.',
      ],
    ),
    Exercise(
      key: 'band_punch_outs',
      label: 'Resistance band punch-outs',
      description:
          'Band anchored behind you. Punch out fast, return under '
          'control.',
      phase: SessionPhase.conditioning,
      defaultDurationSeconds: 120,
      difficulty: 3,
      requiresEquipment: true,
      equipmentNotes: 'Long resistance band with a secure anchor point.',
      categoryWeights: <SkillCategory, double>{
        SkillCategory.power: 0.5,
        SkillCategory.muscularEndurance: 0.3,
        SkillCategory.straight: 0.2,
      },
      cues: <String>[
        'Fast out, controlled back.',
        'Rotate the hips — do not punch with the arm alone.',
        'The band should not pull your guard down.',
      ],
    ),
  ];

  // ----------------------------------------------------------------- shadow

  static const List<Exercise> _shadow = <Exercise>[
    Exercise(
      key: 'shadow_footwork',
      label: 'Shadow — footwork focus',
      description: 'Movement round. Punches exist only to justify the steps.',
      phase: SessionPhase.shadow,
      defaultDurationSeconds: 180,
      difficulty: 2,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.footwork: 0.8,
        SkillCategory.distanceManagement: 0.2,
      },
      cues: <String>[
        'Step off the line after every combination.',
        'Light on your feet. No flat-footed moments.',
        'Move in all four directions, not just forward and back.',
        'Feet land before the punch does.',
      ],
    ),
    Exercise(
      key: 'shadow_defence',
      label: 'Shadow — defence focus',
      description: 'Imagine the return. Every combination is answered.',
      phase: SessionPhase.shadow,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.defence: 0.6,
        SkillCategory.headMovement: 0.4,
      },
      cues: <String>[
        'Slip after every combination.',
        'Roll under the hook.',
        'Head off the centre line.',
        'Defend and move — do not just cover and stand there.',
      ],
    ),
    Exercise(
      key: 'shadow_jab',
      label: 'Shadow — jab focus',
      description:
          'Every variation of the jab: stepping, doubling, to the '
          'body, as a range finder.',
      phase: SessionPhase.shadow,
      defaultDurationSeconds: 180,
      difficulty: 2,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.jab: 0.7,
        SkillCategory.distanceManagement: 0.3,
      },
      cues: <String>[
        'Double up the jab.',
        'Jab and move — never jab and admire it.',
        'Chin behind the shoulder as it goes out.',
        'Change the level. Jab to the body.',
      ],
    ),
    Exercise(
      key: 'shadow_combinations',
      label: 'Shadow — combinations',
      description: 'Three to five punch sequences, finishing with movement.',
      phase: SessionPhase.shadow,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.combinations: 0.6,
        SkillCategory.straight: 0.2,
        SkillCategory.hooks: 0.2,
      },
      cues: <String>[
        'Finish every combination with a step out.',
        'Punches come back — do not leave the hand out there.',
        'Vary the length. Three, then five, then two.',
      ],
    ),
    Exercise(
      key: 'shadow_body_work',
      label: 'Shadow — body work',
      description: 'Level changes, hooks and uppercuts to the body, back out.',
      phase: SessionPhase.shadow,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.hooks: 0.4,
        SkillCategory.uppercuts: 0.2,
        SkillCategory.combinations: 0.2,
        SkillCategory.power: 0.2,
      },
      cues: <String>[
        'Bend the knees to change level, not the back.',
        'Get the head off-line when you come down.',
        'Body, then back upstairs.',
      ],
    ),
    Exercise(
      key: 'shadow_angles',
      label: 'Shadow — angles',
      description: 'Pivot out after combinations, cut off an imaginary ring.',
      phase: SessionPhase.shadow,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.footwork: 0.5,
        SkillCategory.distanceManagement: 0.3,
        SkillCategory.rhythmTiming: 0.2,
      },
      cues: <String>[
        'Pivot on the lead foot after you finish.',
        'Cut the angle — do not follow them in a straight line.',
        'Reset your stance every time you land the pivot.',
      ],
    ),
    Exercise(
      key: 'shadow_counters',
      label: 'Shadow — counters',
      description:
          'Defend first, answer immediately. Slip and return, catch '
          'and return, roll and return.',
      phase: SessionPhase.shadow,
      defaultDurationSeconds: 180,
      difficulty: 4,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.defence: 0.4,
        SkillCategory.combinations: 0.3,
        SkillCategory.rhythmTiming: 0.3,
      },
      cues: <String>[
        'Answer straight away. The counter is late if you think about it.',
        'Slip outside, come back over the top.',
        'Do not counter from where you defended — move first.',
      ],
    ),
    Exercise(
      key: 'shadow_head_movement',
      label: 'Shadow — head movement',
      description:
          'Continuous upper-body movement with punches threaded '
          'through it.',
      phase: SessionPhase.shadow,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.headMovement: 0.7,
        SkillCategory.defence: 0.3,
      },
      cues: <String>[
        'Head never stays in the same place twice.',
        'Move from the legs, not just the neck.',
        'Small movements. You are avoiding a punch, not dodging a car.',
      ],
    ),
    Exercise(
      key: 'shadow_feints',
      label: 'Shadow — feints and rhythm',
      description: 'Break the tempo. Half-shots, level changes, stutter steps.',
      phase: SessionPhase.shadow,
      defaultDurationSeconds: 180,
      difficulty: 4,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.rhythmTiming: 0.6,
        SkillCategory.distanceManagement: 0.4,
      },
      cues: <String>[
        'Sell the feint with the shoulder and the eyes.',
        'Change the rhythm — do not become predictable.',
        'A feint that costs you balance is not a feint.',
      ],
    ),
    Exercise(
      key: 'shadow_high_tempo',
      label: 'Shadow — high tempo',
      description: 'Final-round pace. Output stays high, technique holds.',
      phase: SessionPhase.shadow,
      defaultDurationSeconds: 180,
      difficulty: 4,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.cardio: 0.5,
        SkillCategory.combinations: 0.3,
        SkillCategory.rhythmTiming: 0.2,
      },
      cues: <String>[
        'High output. Keep the hands going.',
        'Technique holds when you are tired — that is the point of this round.',
        'Guard up. Fatigue drops hands first.',
      ],
    ),
  ];

  // -------------------------------------------------------------- technical

  static const List<Exercise> _technical = <Exercise>[
    Exercise(
      key: 'drill_jab_mechanics',
      label: 'Jab mechanics',
      description:
          'Isolated jab. Push off the back foot, hand goes first, '
          'returns on the same line.',
      phase: SessionPhase.technical,
      defaultDurationSeconds: 180,
      difficulty: 2,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.jab: 0.8,
        SkillCategory.straight: 0.2,
      },
      setupCue:
          'Square to your mirror or your camera, front-on. Jab only — '
          'nothing else this round.',
      cues: <String>[
        'Push off the back foot.',
        'Hand leaves before the shoulder turns.',
        'Return to guard on the same line it went out.',
        'Chin down behind the shoulder.',
      ],
    ),
    Exercise(
      key: 'drill_one_two',
      label: 'One-two',
      description:
          'Jab-cross with full hip rotation on the cross and a clean '
          'return on both hands.',
      phase: SessionPhase.technical,
      defaultDurationSeconds: 180,
      difficulty: 2,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.straight: 0.5,
        SkillCategory.jab: 0.3,
        SkillCategory.combinations: 0.2,
      },
      setupCue:
          'Side-on to the camera so the rotation is visible. '
          'Jab-cross, reset, repeat.',
      cues: <String>[
        'Turn the back hip over on the cross.',
        'Rear heel lifts and turns.',
        'Lead hand stays home while the cross goes.',
        'Both hands back before you reset.',
      ],
    ),
    Exercise(
      key: 'drill_guard_return',
      label: 'Guard return under fatigue',
      description:
          'Throw a combination, freeze, check the guard, repeat. '
          'Deliberately boring, deliberately useful.',
      phase: SessionPhase.technical,
      defaultDurationSeconds: 180,
      difficulty: 2,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.defence: 0.6,
        SkillCategory.combinations: 0.2,
        SkillCategory.jab: 0.2,
      },
      setupCue:
          'Combination, then hold your finishing position for a beat and '
          'check both hands are where they should be.',
      cues: <String>[
        'Freeze. Where are your hands?',
        'The hand that just punched is the one that drops. Watch it.',
        'Guard back before you move, not after.',
      ],
    ),
    Exercise(
      key: 'drill_slip_rope',
      label: 'Slipping',
      description:
          'Slip left and right off a straight punch, staying in '
          'stance and in range.',
      phase: SessionPhase.technical,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.headMovement: 0.6,
        SkillCategory.defence: 0.4,
      },
      setupCue:
          'Slip line or an imaginary one at chin height. Slip, do not '
          'duck.',
      cues: <String>[
        'Bend the knees, not the waist.',
        'Eyes stay on the target through the slip.',
        'Come back to centre ready to punch.',
      ],
    ),
    Exercise(
      key: 'drill_roll_under',
      label: 'Rolling under hooks',
      description:
          'Roll under an imaginary hook and come up on the other '
          'side, in balance.',
      phase: SessionPhase.technical,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.defence: 0.5,
        SkillCategory.headMovement: 0.5,
      },
      setupCue:
          'Roll under and across. Come up in stance, hands up, ready to '
          'answer.',
      cues: <String>[
        'Roll through, do not bob straight down and back up.',
        'Guard stays tight through the roll.',
        'Come up punching.',
      ],
    ),
    Exercise(
      key: 'drill_pivot',
      label: 'Pivot off the lead foot',
      description:
          'Land a combination, pivot forty-five degrees, reset stance.',
      phase: SessionPhase.technical,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.footwork: 0.7,
        SkillCategory.distanceManagement: 0.3,
      },
      setupCue:
          'Full body in frame including your feet — this drill lives '
          'below the waist.',
      cues: <String>[
        'Pivot on the ball of the lead foot.',
        'Rear foot swings round, stance stays the same width.',
        'Hands up through the pivot.',
      ],
    ),
    Exercise(
      key: 'drill_hook_mechanics',
      label: 'Hook mechanics',
      description:
          'Lead hook: turn the foot, turn the hip, elbow at shoulder '
          'height, short arc.',
      phase: SessionPhase.technical,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.hooks: 0.9,
        SkillCategory.power: 0.1,
      },
      setupCue: 'Side-on. Lead hook only, slow before fast.',
      cues: <String>[
        'Turn the lead foot with the punch.',
        'Elbow at shoulder height, arm stays short.',
        'Do not wind it up — it starts from the guard.',
        'Rear hand covers the chin the whole time.',
      ],
    ),
    Exercise(
      key: 'drill_uppercut_mechanics',
      label: 'Uppercut mechanics',
      description:
          'Small dip, drive up through the legs, short punch. No '
          'winding up.',
      phase: SessionPhase.technical,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.uppercuts: 0.9,
        SkillCategory.power: 0.1,
      },
      setupCue: 'Front-on. Alternate lead and rear uppercut, reset between.',
      cues: <String>[
        'Dip with the knees, not the shoulders.',
        'Short punch. It travels a hand span.',
        'Do not drop the hand to load it.',
      ],
    ),
    Exercise(
      key: 'drill_step_jab',
      label: 'Stepping jab',
      description:
          'Jab arriving with the step, closing distance without '
          'falling in.',
      phase: SessionPhase.technical,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.jab: 0.5,
        SkillCategory.footwork: 0.3,
        SkillCategory.distanceManagement: 0.2,
      },
      setupCue: 'Work a line on the floor. Step and jab together, then out.',
      cues: <String>[
        'Foot and hand land together.',
        'Do not lean in — bring your feet with you.',
        'Straight back out afterwards.',
      ],
    ),
    Exercise(
      key: 'drill_double_jab',
      label: 'Double jab',
      description:
          'Two jabs with different intent: the first measures, the '
          'second means it.',
      phase: SessionPhase.technical,
      defaultDurationSeconds: 180,
      difficulty: 3,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.jab: 0.7,
        SkillCategory.rhythmTiming: 0.3,
      },
      setupCue: 'Double jab, reset, repeat. Vary the gap between the two.',
      cues: <String>[
        'First one light, second one sharp.',
        'Hand comes most of the way back between them.',
        'Change the timing so it is not always the same beat.',
      ],
    ),
    Exercise(
      key: 'drill_check_hook',
      label: 'Check hook',
      description:
          'Pivot away while landing the lead hook on someone coming '
          'forward.',
      phase: SessionPhase.technical,
      defaultDurationSeconds: 180,
      difficulty: 4,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.hooks: 0.4,
        SkillCategory.footwork: 0.3,
        SkillCategory.defence: 0.3,
      },
      setupCue: 'Imagine pressure coming forward. Hook and pivot in one move.',
      cues: <String>[
        'Pivot and punch together, not one then the other.',
        'Weight moves onto the lead foot as it turns.',
        'Finish facing them, hands up.',
      ],
    ),
    Exercise(
      key: 'drill_in_and_out',
      label: 'Distance — in and out',
      description:
          'Enter with a shot, exit before the return. Range discipline '
          'drill.',
      phase: SessionPhase.technical,
      defaultDurationSeconds: 180,
      difficulty: 4,
      categoryWeights: <SkillCategory, double>{
        SkillCategory.distanceManagement: 0.7,
        SkillCategory.footwork: 0.3,
      },
      setupCue:
          'Mark a spot as your opponent. Touch range, then out of range. '
          'No standing in between.',
      cues: <String>[
        'In and out. Never linger at mid-range.',
        'Out on the same angle you came in? Fix that — leave on a different one.',
        'Guard is highest on the way out.',
      ],
    ),
  ];

  // -------------------------------------------------------------- cool-down

  static const List<Exercise> _coolDown = <Exercise>[
    Exercise(
      key: 'breathing_reset',
      label: 'Breathing reset',
      description:
          'Standing or lying. Four seconds in, six seconds out, until '
          'the heart rate drops.',
      phase: SessionPhase.coolDown,
      defaultDurationSeconds: 90,
      difficulty: 1,
      categoryWeights: <SkillCategory, double>{SkillCategory.mobility: 1.0},
      cues: <String>[
        'In through the nose for four, out for six.',
        'Let the shoulders drop.',
      ],
    ),
    Exercise(
      key: 'shoulder_stretch',
      label: 'Shoulder and chest stretch',
      description:
          'Cross-body and doorway stretches. Thirty seconds each side.',
      phase: SessionPhase.coolDown,
      defaultDurationSeconds: 90,
      difficulty: 1,
      categoryWeights: <SkillCategory, double>{SkillCategory.mobility: 1.0},
      cues: <String>[
        'Thirty seconds each side. Long holds now.',
        'Breathe into the stretch, do not fight it.',
      ],
    ),
    Exercise(
      key: 'hip_flexor_stretch',
      label: 'Hip flexor stretch',
      description: 'Half-kneeling, hips square, gentle press forward.',
      phase: SessionPhase.coolDown,
      defaultDurationSeconds: 90,
      difficulty: 1,
      categoryWeights: <SkillCategory, double>{SkillCategory.mobility: 1.0},
      cues: <String>[
        'Squeeze the glute on the kneeling side.',
        'Do not arch the low back to feel more.',
      ],
    ),
    Exercise(
      key: 'hamstring_stretch',
      label: 'Hamstring and calf stretch',
      description: 'Seated or standing, plus a wall calf stretch.',
      phase: SessionPhase.coolDown,
      defaultDurationSeconds: 90,
      difficulty: 1,
      categoryWeights: <SkillCategory, double>{SkillCategory.mobility: 1.0},
      cues: <String>[
        'Long spine. Hinge from the hip.',
        'Calves take a beating from skipping — give them the full thirty.',
      ],
    ),
    Exercise(
      key: 'neck_and_traps',
      label: 'Neck and traps',
      description: 'Gentle lateral and rotational holds. No forcing, ever.',
      phase: SessionPhase.coolDown,
      defaultDurationSeconds: 60,
      difficulty: 1,
      categoryWeights: <SkillCategory, double>{SkillCategory.mobility: 1.0},
      cues: <String>[
        'Gentle. Never pull on your own head.',
        'Both sides, equal time.',
      ],
    ),
    Exercise(
      key: 'session_reflection',
      label: 'Session reflection',
      description:
          'Stand still. What went well, what was scrappy, what to '
          'work on next time.',
      phase: SessionPhase.coolDown,
      defaultDurationSeconds: 60,
      difficulty: 1,
      categoryWeights: <SkillCategory, double>{SkillCategory.mobility: 1.0},
      cues: <String>[
        'One thing that felt sharp today. One thing to fix.',
        'Note it down before you forget it.',
      ],
    ),
  ];
}
