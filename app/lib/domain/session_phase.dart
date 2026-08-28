import '../analysis/session_type.dart';

/// The five-phase session arc from the spec.
///
/// Every full session follows this arc in order. Warm-up is never skipped.
enum SessionPhase {
  warmUp(
    key: 'warmup',
    label: 'Warm-up',
    intent: 'Progressive activation. Never skipped.',
    coachIntro:
        'Warm-up. Easy pace, full range. We are switching the body on, '
        'not training yet.',
    structure: PhaseStructure.continuous,
  ),
  conditioning(
    key: 'conditioning',
    label: 'Conditioning',
    intent: 'Physical prep for the boxing work. Round structure starts here.',
    coachIntro:
        'Conditioning. Round structure from here. '
        'Work hard, recover properly in the rest.',
    structure: PhaseStructure.rounds,
  ),
  shadow(
    key: 'shadow',
    label: 'Shadow boxing',
    intent:
        'Skill development without impact. Themed rounds, '
        'progressive intensity.',
    coachIntro:
        'Shadow boxing. Each round has a theme. '
        'Quality over speed — make it look like boxing.',
    structure: PhaseStructure.rounds,
  ),
  technical(
    key: 'technical',
    label: 'Technical work',
    intent: 'Focused drill work on one technique at a time.',
    coachIntro:
        'Technical work. One thing at a time, done properly. '
        'Slow is fine — sloppy is not.',
    structure: PhaseStructure.rounds,
  ),
  coolDown(
    key: 'cooldown',
    label: 'Cool-down',
    intent: 'Static stretching, breathing, session summary.',
    coachIntro:
        'Cool-down. Long holds, nose breathing. '
        'This is part of the session, not an afterthought.',
    structure: PhaseStructure.continuous,
  );

  const SessionPhase({
    required this.key,
    required this.label,
    required this.intent,
    required this.coachIntro,
    required this.structure,
  });

  /// Stable identifier — matches `session_rounds.phase` in the spec's schema.
  final String key;
  final String label;

  /// What the phase is for. Shown on the template breakdown.
  final String intent;

  /// Spoken by the coach when the phase begins.
  final String coachIntro;

  final PhaseStructure structure;

  bool get isRoundBased => structure == PhaseStructure.rounds;

  /// Configuration limits. The spec gives each phase a duration range
  /// ("Warm-up (5-10 minutes)"); for round-based phases that range is expressed
  /// as a round count at a 2-3 minute round length, which is how boxers
  /// actually configure a session.
  PhaseBounds get bounds => switch (this) {
    SessionPhase.warmUp => const PhaseBounds(
      minTotalSeconds: 300,
      maxTotalSeconds: 600,
    ),
    SessionPhase.conditioning => const PhaseBounds(
      minRounds: 3,
      maxRounds: 8,
      minWorkSeconds: 60,
      maxWorkSeconds: 180,
      minRestSeconds: 30,
      maxRestSeconds: 90,
    ),
    SessionPhase.shadow => const PhaseBounds(
      minRounds: 3,
      maxRounds: 8,
      minWorkSeconds: 120,
      maxWorkSeconds: 180,
      minRestSeconds: 30,
      maxRestSeconds: 60,
    ),
    SessionPhase.technical => const PhaseBounds(
      minRounds: 3,
      maxRounds: 10,
      minWorkSeconds: 120,
      maxWorkSeconds: 180,
      minRestSeconds: 30,
      maxRestSeconds: 90,
    ),
    SessionPhase.coolDown => const PhaseBounds(
      minTotalSeconds: 300,
      maxTotalSeconds: 600,
    ),
  };

  /// Whether the phase may be turned off in the session configuration.
  ///
  /// The spec is explicit that the warm-up is never skipped, and a cool-down
  /// that can be dropped is a cool-down that never happens.
  bool get isOptional => isRoundBased;

  /// The analysis intent for a round recorded during this phase (brief §4).
  /// This is how a guided-session round gets its [SessionType]; standalone
  /// recordings set one directly. Non-boxing phases (warm-up, cool-down) are
  /// not recorded for analysis, so they map to free training.
  SessionType get sessionType => switch (this) {
    SessionPhase.shadow => SessionType.shadowBoxing,
    SessionPhase.technical => SessionType.technicalWork,
    SessionPhase.conditioning => SessionType.heavyBag,
    SessionPhase.warmUp || SessionPhase.coolDown => SessionType.freeTraining,
  };

  static SessionPhase? fromKey(String key) {
    for (final phase in SessionPhase.values) {
      if (phase.key == key) return phase;
    }
    return null;
  }
}

enum PhaseStructure {
  /// An uninterrupted sequence of exercises (warm-up, cool-down).
  continuous,

  /// Work/rest rounds (conditioning, shadow, technical).
  rounds,
}

/// The "reasonable bounds" a phase's duration is configurable within.
class PhaseBounds {
  const PhaseBounds({
    this.minTotalSeconds = 0,
    this.maxTotalSeconds = 0,
    this.minRounds = 0,
    this.maxRounds = 0,
    this.minWorkSeconds = 0,
    this.maxWorkSeconds = 0,
    this.minRestSeconds = 0,
    this.maxRestSeconds = 0,
  });

  final int minTotalSeconds;
  final int maxTotalSeconds;
  final int minRounds;
  final int maxRounds;
  final int minWorkSeconds;
  final int maxWorkSeconds;
  final int minRestSeconds;
  final int maxRestSeconds;

  int clampTotal(int seconds) =>
      seconds.clamp(minTotalSeconds, maxTotalSeconds);

  int clampRounds(int rounds) => rounds.clamp(minRounds, maxRounds);

  int clampWork(int seconds) => seconds.clamp(minWorkSeconds, maxWorkSeconds);

  int clampRest(int seconds) => seconds.clamp(minRestSeconds, maxRestSeconds);
}
