import '../domain/session_phase.dart';
import '../domain/session_template.dart';
import '../domain/skill_category.dart';

/// The pre-built sessions shipped with v0.1.
///
/// Open question 5 in the spec recommends templates for the MVP — the user
/// picks, they do not build. Every template runs the full five-phase arc; they
/// differ in where the time goes and what the themed rounds are.
class SessionTemplates {
  const SessionTemplates._();

  static const List<SessionTemplate> all = <SessionTemplate>[
    balancedFull,
    conditioningBlock,
    defenceAndHeadMovement,
    footworkAndDistance,
    shortSharp,
  ];

  static SessionTemplate? byId(String id) {
    for (final template in all) {
      if (template.id == id) return template;
    }
    return null;
  }

  // ------------------------------------------------------------------------

  static const SessionTemplate balancedFull = SessionTemplate(
    id: 'balanced_full',
    name: 'Full Session — Balanced',
    tagline: 'The default hour. Everything gets a turn.',
    description:
        'The complete arc with no particular bias: enough '
        'conditioning to matter, four themed shadow rounds, and a technical '
        'block on the fundamentals. Use this as your baseline session and let '
        'the focused templates fill the gaps.',
    focus: <SkillCategory>[
      SkillCategory.combinations,
      SkillCategory.jab,
      SkillCategory.footwork,
      SkillCategory.defence,
    ],
    difficulty: 3,
    phases: <TemplatePhase>[
      TemplatePhase(
        phase: SessionPhase.warmUp,
        defaultTotalSeconds: 480,
        items: <PhaseItem>[
          PhaseItem('joint_circles'),
          PhaseItem('arm_swings'),
          PhaseItem('light_skipping'),
          PhaseItem('hip_openers'),
          PhaseItem('dynamic_stretch'),
          PhaseItem('stance_and_steps'),
          PhaseItem('shadow_activation'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.conditioning,
        intent:
            'Four rounds of bodyweight work. Enough to prepare you, not '
            'enough to ruin the boxing.',
        defaultRounds: 4,
        defaultWorkSeconds: 120,
        defaultRestSeconds: 45,
        items: <PhaseItem>[
          PhaseItem('push_ups', theme: 'Upper body endurance'),
          PhaseItem('squat_jumps', theme: 'Leg power'),
          PhaseItem('burpees', theme: 'Full body'),
          PhaseItem('plank', theme: 'Trunk'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.shadow,
        intent: 'Four themed rounds, intensity climbing across them.',
        defaultRounds: 4,
        defaultWorkSeconds: 180,
        defaultRestSeconds: 60,
        items: <PhaseItem>[
          PhaseItem('shadow_footwork', theme: 'Footwork focus'),
          PhaseItem('shadow_jab', theme: 'Jab focus'),
          PhaseItem('shadow_defence', theme: 'Defence focus'),
          PhaseItem('shadow_combinations', theme: 'Combinations'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.technical,
        intent:
            'Fundamentals, one at a time. This is the block the camera '
            'will watch from v0.5.',
        defaultRounds: 5,
        defaultWorkSeconds: 180,
        defaultRestSeconds: 60,
        items: <PhaseItem>[
          PhaseItem('drill_jab_mechanics', theme: 'Jab mechanics'),
          PhaseItem('drill_one_two', theme: 'One-two'),
          PhaseItem('drill_guard_return', theme: 'Guard return'),
          PhaseItem('drill_slip_rope', theme: 'Slipping'),
          PhaseItem('drill_pivot', theme: 'Pivots'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.coolDown,
        defaultTotalSeconds: 360,
        items: <PhaseItem>[
          PhaseItem('breathing_reset'),
          PhaseItem('shoulder_stretch'),
          PhaseItem('hip_flexor_stretch'),
          PhaseItem('hamstring_stretch'),
          PhaseItem('session_reflection'),
        ],
      ),
    ],
  );

  // ------------------------------------------------------------------------

  static const SessionTemplate conditioningBlock = SessionTemplate(
    id: 'conditioning_block',
    name: 'Conditioning Block',
    tagline: 'Six hard rounds, then box through the fatigue.',
    description:
        'For a conditioning phase of training. The heavy work comes '
        'early and the boxing that follows is deliberately done tired — that '
        'is where technique either holds or falls apart. Technical block kept '
        'short and simple on purpose.',
    focus: <SkillCategory>[
      SkillCategory.cardio,
      SkillCategory.muscularEndurance,
      SkillCategory.power,
    ],
    difficulty: 5,
    phases: <TemplatePhase>[
      TemplatePhase(
        phase: SessionPhase.warmUp,
        defaultTotalSeconds: 480,
        items: <PhaseItem>[
          PhaseItem('joint_circles'),
          PhaseItem('jumping_jacks'),
          PhaseItem('light_skipping'),
          PhaseItem('hip_openers'),
          PhaseItem('dynamic_stretch'),
          PhaseItem('shadow_activation'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.conditioning,
        intent: 'Six rounds. Pace it — the first two are not the session.',
        defaultRounds: 6,
        defaultWorkSeconds: 150,
        defaultRestSeconds: 45,
        items: <PhaseItem>[
          PhaseItem('skipping_intervals', theme: 'Interval skipping'),
          PhaseItem('burpees', theme: 'Full body'),
          PhaseItem('push_ups', theme: 'Upper body endurance'),
          PhaseItem('mountain_climbers', theme: 'Engine'),
          PhaseItem('squat_jumps', theme: 'Leg power'),
          PhaseItem('sprawl_and_shadow', theme: 'Up and punching'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.shadow,
        intent: 'Box tired. Output stays up, hands stay up.',
        defaultRounds: 4,
        defaultWorkSeconds: 180,
        defaultRestSeconds: 45,
        items: <PhaseItem>[
          PhaseItem('shadow_high_tempo', theme: 'High tempo'),
          PhaseItem('shadow_combinations', theme: 'Combinations'),
          PhaseItem('shadow_footwork', theme: 'Footwork under fatigue'),
          PhaseItem('shadow_high_tempo', theme: 'Empty the tank'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.technical,
        intent: 'Three rounds on the basics. Fatigue exposes them.',
        defaultRounds: 3,
        defaultWorkSeconds: 180,
        defaultRestSeconds: 60,
        items: <PhaseItem>[
          PhaseItem('drill_guard_return', theme: 'Guard return'),
          PhaseItem('drill_one_two', theme: 'One-two'),
          PhaseItem('drill_jab_mechanics', theme: 'Jab mechanics'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.coolDown,
        defaultTotalSeconds: 420,
        items: <PhaseItem>[
          PhaseItem('breathing_reset'),
          PhaseItem('hamstring_stretch'),
          PhaseItem('hip_flexor_stretch'),
          PhaseItem('shoulder_stretch'),
          PhaseItem('neck_and_traps'),
          PhaseItem('session_reflection'),
        ],
      ),
    ],
  );

  // ------------------------------------------------------------------------

  static const SessionTemplate defenceAndHeadMovement = SessionTemplate(
    id: 'defence_head_movement',
    name: 'Defence & Head Movement',
    tagline: 'Get harder to hit.',
    description:
        'Most people train offence and call it boxing. This session '
        'is the correction: light conditioning, three defensive shadow rounds, '
        'and a long technical block on slipping, rolling and guard discipline.',
    focus: <SkillCategory>[
      SkillCategory.defence,
      SkillCategory.headMovement,
      SkillCategory.footwork,
    ],
    difficulty: 3,
    phases: <TemplatePhase>[
      TemplatePhase(
        phase: SessionPhase.warmUp,
        defaultTotalSeconds: 420,
        items: <PhaseItem>[
          PhaseItem('joint_circles'),
          PhaseItem('arm_swings'),
          PhaseItem('jog_in_place'),
          PhaseItem('hip_openers'),
          PhaseItem('stance_and_steps'),
          PhaseItem('shadow_activation'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.conditioning,
        intent: 'Trunk and posture work only — the legs are needed later.',
        defaultRounds: 3,
        defaultWorkSeconds: 120,
        defaultRestSeconds: 45,
        items: <PhaseItem>[
          PhaseItem('plank', theme: 'Trunk'),
          PhaseItem('mountain_climbers', theme: 'Engine'),
          PhaseItem('hollow_hold', theme: 'Trunk'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.shadow,
        intent: 'Defend first, punch second, all four rounds.',
        defaultRounds: 4,
        defaultWorkSeconds: 180,
        defaultRestSeconds: 60,
        items: <PhaseItem>[
          PhaseItem('shadow_defence', theme: 'Defence focus'),
          PhaseItem('shadow_head_movement', theme: 'Head movement'),
          PhaseItem('shadow_counters', theme: 'Counters'),
          PhaseItem('shadow_defence', theme: 'Defence under pressure'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.technical,
        intent: 'Five rounds on the defensive fundamentals.',
        defaultRounds: 5,
        defaultWorkSeconds: 180,
        defaultRestSeconds: 60,
        items: <PhaseItem>[
          PhaseItem('drill_slip_rope', theme: 'Slipping'),
          PhaseItem('drill_roll_under', theme: 'Rolling'),
          PhaseItem('drill_guard_return', theme: 'Guard return'),
          PhaseItem('drill_check_hook', theme: 'Check hook'),
          PhaseItem(
            'drill_slip_rope',
            theme: 'Slip and counter',
            note:
                'Same slip as round one, but answer with a straight every '
                'time you come back to centre.',
          ),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.coolDown,
        defaultTotalSeconds: 360,
        items: <PhaseItem>[
          PhaseItem('breathing_reset'),
          PhaseItem('neck_and_traps'),
          PhaseItem('shoulder_stretch'),
          PhaseItem('hip_flexor_stretch'),
          PhaseItem('session_reflection'),
        ],
      ),
    ],
  );

  // ------------------------------------------------------------------------

  static const SessionTemplate footworkAndDistance = SessionTemplate(
    id: 'footwork_distance',
    name: 'Footwork & Distance',
    tagline: 'Win the space before you throw anything.',
    description:
        'Everything below the waist, plus the range discipline that '
        'depends on it. Expect to cover ground — you want floor space for this '
        'one.',
    focus: <SkillCategory>[
      SkillCategory.footwork,
      SkillCategory.distanceManagement,
      SkillCategory.rhythmTiming,
    ],
    difficulty: 4,
    phases: <TemplatePhase>[
      TemplatePhase(
        phase: SessionPhase.warmUp,
        defaultTotalSeconds: 420,
        items: <PhaseItem>[
          PhaseItem('joint_circles'),
          PhaseItem('light_skipping'),
          PhaseItem('hip_openers'),
          PhaseItem('dynamic_stretch'),
          PhaseItem('stance_and_steps'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.conditioning,
        intent: 'Legs and feet. Everything here pays off in the next hour.',
        defaultRounds: 3,
        defaultWorkSeconds: 150,
        defaultRestSeconds: 45,
        items: <PhaseItem>[
          PhaseItem('footwork_in_out', theme: 'In and out'),
          PhaseItem('skipping_intervals', theme: 'Interval skipping'),
          PhaseItem('squat_jumps', theme: 'Leg power'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.shadow,
        intent: 'Movement rounds. Punches are there to justify the steps.',
        defaultRounds: 4,
        defaultWorkSeconds: 180,
        defaultRestSeconds: 45,
        items: <PhaseItem>[
          PhaseItem('shadow_footwork', theme: 'Footwork focus'),
          PhaseItem('shadow_angles', theme: 'Angles'),
          PhaseItem('shadow_feints', theme: 'Feints and rhythm'),
          PhaseItem('shadow_footwork', theme: 'Ring cutting'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.technical,
        intent: 'Four rounds where the feet are the technique.',
        defaultRounds: 4,
        defaultWorkSeconds: 180,
        defaultRestSeconds: 60,
        items: <PhaseItem>[
          PhaseItem('drill_pivot', theme: 'Pivots'),
          PhaseItem('drill_step_jab', theme: 'Stepping jab'),
          PhaseItem('drill_in_and_out', theme: 'Range discipline'),
          PhaseItem('drill_check_hook', theme: 'Check hook'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.coolDown,
        defaultTotalSeconds: 300,
        items: <PhaseItem>[
          PhaseItem('breathing_reset'),
          PhaseItem('hamstring_stretch'),
          PhaseItem('hip_flexor_stretch'),
          PhaseItem('session_reflection'),
        ],
      ),
    ],
  );

  // ------------------------------------------------------------------------

  static const SessionTemplate shortSharp = SessionTemplate(
    id: 'short_sharp',
    name: 'Short & Sharp',
    tagline: 'Thirty minutes, full arc, nothing skipped.',
    description:
        'The session for the day you have half an hour. Shorter '
        'rounds and shorter rest rather than a missing phase — the arc is the '
        'point, and a warm-up you skip is an injury you book.',
    focus: <SkillCategory>[
      SkillCategory.cardio,
      SkillCategory.combinations,
      SkillCategory.jab,
    ],
    difficulty: 2,
    phases: <TemplatePhase>[
      TemplatePhase(
        phase: SessionPhase.warmUp,
        defaultTotalSeconds: 300,
        items: <PhaseItem>[
          PhaseItem('joint_circles'),
          PhaseItem('jumping_jacks'),
          PhaseItem('dynamic_stretch'),
          PhaseItem('shadow_activation'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.conditioning,
        intent: 'Three short rounds. Short does not mean easy.',
        defaultRounds: 3,
        defaultWorkSeconds: 60,
        defaultRestSeconds: 30,
        items: <PhaseItem>[
          PhaseItem('burpees', theme: 'Full body'),
          PhaseItem('push_ups', theme: 'Upper body endurance'),
          PhaseItem('mountain_climbers', theme: 'Engine'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.shadow,
        intent: 'Three two-minute rounds.',
        defaultRounds: 3,
        defaultWorkSeconds: 120,
        defaultRestSeconds: 30,
        items: <PhaseItem>[
          PhaseItem('shadow_footwork', theme: 'Footwork focus'),
          PhaseItem('shadow_combinations', theme: 'Combinations'),
          PhaseItem('shadow_high_tempo', theme: 'High tempo'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.technical,
        intent: 'Three rounds on the two punches you throw most.',
        defaultRounds: 3,
        defaultWorkSeconds: 120,
        defaultRestSeconds: 30,
        items: <PhaseItem>[
          PhaseItem('drill_jab_mechanics', theme: 'Jab mechanics'),
          PhaseItem('drill_one_two', theme: 'One-two'),
          PhaseItem('drill_guard_return', theme: 'Guard return'),
        ],
      ),
      TemplatePhase(
        phase: SessionPhase.coolDown,
        defaultTotalSeconds: 300,
        items: <PhaseItem>[
          PhaseItem('breathing_reset'),
          PhaseItem('shoulder_stretch'),
          PhaseItem('hamstring_stretch'),
          PhaseItem('session_reflection'),
        ],
      ),
    ],
  );
}
