import 'session_phase.dart';
import 'session_template.dart';

/// User configuration for one phase of a session.
///
/// Every value is clamped to the phase's [PhaseBounds] on construction, so an
/// invalid configuration cannot reach the timeline builder — the spec allows
/// durations to be configurable "within reasonable bounds", and the bounds are
/// enforced here rather than trusted to the UI.
class PhaseSettings {
  factory PhaseSettings({
    required SessionPhase phase,
    bool enabled = true,
    int rounds = 0,
    int workSeconds = 0,
    int restSeconds = 0,
    int totalSeconds = 0,
  }) {
    final bounds = phase.bounds;
    return PhaseSettings._(
      phase: phase,
      enabled: phase.isOptional ? enabled : true,
      rounds: phase.isRoundBased ? bounds.clampRounds(rounds) : 0,
      workSeconds: phase.isRoundBased ? bounds.clampWork(workSeconds) : 0,
      restSeconds: phase.isRoundBased ? bounds.clampRest(restSeconds) : 0,
      totalSeconds: phase.isRoundBased ? 0 : bounds.clampTotal(totalSeconds),
    );
  }

  const PhaseSettings._({
    required this.phase,
    required this.enabled,
    required this.rounds,
    required this.workSeconds,
    required this.restSeconds,
    required this.totalSeconds,
  });

  /// The template's defaults, clamped into range.
  factory PhaseSettings.fromTemplate(TemplatePhase templatePhase) {
    return PhaseSettings(
      phase: templatePhase.phase,
      rounds: templatePhase.defaultRounds,
      workSeconds: templatePhase.defaultWorkSeconds,
      restSeconds: templatePhase.defaultRestSeconds,
      totalSeconds: templatePhase.defaultTotalSeconds,
    );
  }

  final SessionPhase phase;
  final bool enabled;
  final int rounds;
  final int workSeconds;
  final int restSeconds;
  final int totalSeconds;

  PhaseSettings copyWith({
    bool? enabled,
    int? rounds,
    int? workSeconds,
    int? restSeconds,
    int? totalSeconds,
  }) {
    return PhaseSettings(
      phase: phase,
      enabled: enabled ?? this.enabled,
      rounds: rounds ?? this.rounds,
      workSeconds: workSeconds ?? this.workSeconds,
      restSeconds: restSeconds ?? this.restSeconds,
      totalSeconds: totalSeconds ?? this.totalSeconds,
    );
  }

  /// Total wall-clock time this phase contributes, rest included.
  ///
  /// The final rest of a round-based phase is kept: it is the transition into
  /// the next phase, and the coach uses it to preview what is coming.
  Duration get duration {
    if (!enabled) return Duration.zero;
    if (phase.isRoundBased) {
      return Duration(seconds: rounds * (workSeconds + restSeconds));
    }
    return Duration(seconds: totalSeconds);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'phase': phase.key,
    'enabled': enabled,
    'rounds': rounds,
    'workSeconds': workSeconds,
    'restSeconds': restSeconds,
    'totalSeconds': totalSeconds,
  };

  static PhaseSettings? fromJson(Map<String, Object?> json) {
    final phase = SessionPhase.fromKey(json['phase'] as String? ?? '');
    if (phase == null) return null;
    return PhaseSettings(
      phase: phase,
      enabled: json['enabled'] as bool? ?? true,
      rounds: json['rounds'] as int? ?? 0,
      workSeconds: json['workSeconds'] as int? ?? 0,
      restSeconds: json['restSeconds'] as int? ?? 0,
      totalSeconds: json['totalSeconds'] as int? ?? 0,
    );
  }
}

/// The full configuration for a session about to be run.
class SessionSettings {
  SessionSettings({
    required List<PhaseSettings> phases,
    this.voiceEnabled = true,
    this.soundEnabled = true,
  }) : phases = List<PhaseSettings>.unmodifiable(phases);

  /// Defaults taken from the template, in arc order.
  factory SessionSettings.fromTemplate(SessionTemplate template) {
    return SessionSettings(
      phases: <PhaseSettings>[
        for (final templatePhase in template.phases)
          PhaseSettings.fromTemplate(templatePhase),
      ],
    );
  }

  final List<PhaseSettings> phases;

  /// Spoken coaching. Sounds stay on when this is off, so the timer still works
  /// with a podcast in your ears.
  final bool voiceEnabled;

  /// Bells and countdown ticks.
  final bool soundEnabled;

  PhaseSettings? forPhase(SessionPhase phase) {
    for (final settings in phases) {
      if (settings.phase == phase) return settings;
    }
    return null;
  }

  Duration get totalDuration => phases.fold(
    Duration.zero,
    (total, settings) => total + settings.duration,
  );

  SessionSettings withPhase(PhaseSettings updated) {
    return SessionSettings(
      phases: <PhaseSettings>[
        for (final settings in phases)
          if (settings.phase == updated.phase) updated else settings,
      ],
      voiceEnabled: voiceEnabled,
      soundEnabled: soundEnabled,
    );
  }

  SessionSettings copyWith({bool? voiceEnabled, bool? soundEnabled}) {
    return SessionSettings(
      phases: phases,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'voiceEnabled': voiceEnabled,
    'soundEnabled': soundEnabled,
    'phases': <Object?>[for (final settings in phases) settings.toJson()],
  };

  /// Rebuilds settings from storage, falling back to the template for any
  /// phase the stored payload does not cover (templates change between builds).
  static SessionSettings fromJson(
    Map<String, Object?> json,
    SessionTemplate template,
  ) {
    final stored = <SessionPhase, PhaseSettings>{};
    final rawPhases = json['phases'];
    if (rawPhases is List) {
      for (final entry in rawPhases) {
        if (entry is Map) {
          final settings = PhaseSettings.fromJson(
            entry.cast<String, Object?>(),
          );
          if (settings != null) stored[settings.phase] = settings;
        }
      }
    }
    return SessionSettings(
      phases: <PhaseSettings>[
        for (final templatePhase in template.phases)
          stored[templatePhase.phase] ??
              PhaseSettings.fromTemplate(templatePhase),
      ],
      voiceEnabled: json['voiceEnabled'] as bool? ?? true,
      soundEnabled: json['soundEnabled'] as bool? ?? true,
    );
  }
}
