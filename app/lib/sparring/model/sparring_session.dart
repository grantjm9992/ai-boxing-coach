import '../tracking/identity_linker.dart';
import 'fighter.dart';

/// How a sparring session is run.
class SparringSettings {
  const SparringSettings({
    this.rounds = 3,
    this.roundSeconds = 180,
    this.restSeconds = 60,
    this.aiReview = true,
  });

  final int rounds;
  final int roundSeconds;
  final int restSeconds;

  /// Run the AI coach's review on each round (one weekly AI analysis per
  /// round, from the same allowance as everything else).
  final bool aiReview;

  SparringSettings copyWith({int? rounds, int? roundSeconds, int? restSeconds, bool? aiReview}) =>
      SparringSettings(
        rounds: rounds ?? this.rounds,
        roundSeconds: roundSeconds ?? this.roundSeconds,
        restSeconds: restSeconds ?? this.restSeconds,
        aiReview: aiReview ?? this.aiReview,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'rounds': rounds,
    'roundSeconds': roundSeconds,
    'restSeconds': restSeconds,
    'aiReview': aiReview,
  };

  factory SparringSettings.fromJson(Map<String, Object?> json) => SparringSettings(
    rounds: (json['rounds'] as num?)?.toInt() ?? 3,
    roundSeconds: (json['roundSeconds'] as num?)?.toInt() ?? 180,
    restSeconds: (json['restSeconds'] as num?)?.toInt() ?? 60,
    aiReview: json['aiReview'] != false,
  );
}

/// Where a round's processing is.
enum SparringRoundStatus {
  recorded('recorded', 'Waiting'),
  extracting('extracting', 'Finding both fighters'),
  tracking('tracking', 'Working out who is who'),
  analysing('analysing', 'Measuring both fighters'),
  reviewing('reviewing', 'AI coach reviewing'),
  done('done', 'Ready'),
  failed('failed', 'Failed');

  const SparringRoundStatus(this.value, this.label);
  final String value;
  final String label;

  bool get isBusy =>
      this != SparringRoundStatus.recorded &&
      this != SparringRoundStatus.done &&
      this != SparringRoundStatus.failed;

  static SparringRoundStatus fromValue(Object? value) => SparringRoundStatus.values
      .firstWhere((s) => s.value == value, orElse: () => SparringRoundStatus.recorded);
}

/// One recorded round of a session.
class SparringRound {
  const SparringRound({
    required this.number,
    required this.recordedAt,
    this.durationMs,
    this.status = SparringRoundStatus.recorded,
    this.error,
    this.synced = false,
  });

  /// 1-based.
  final int number;
  final DateTime recordedAt;
  final double? durationMs;
  final SparringRoundStatus status;
  final String? error;
  final bool synced;

  SparringRound copyWith({
    double? durationMs,
    SparringRoundStatus? status,
    String? error,
    bool clearError = false,
    bool? synced,
  }) => SparringRound(
    number: number,
    recordedAt: recordedAt,
    durationMs: durationMs ?? this.durationMs,
    status: status ?? this.status,
    error: clearError ? null : (error ?? this.error),
    synced: synced ?? this.synced,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'number': number,
    'recordedAt': recordedAt.toIso8601String(),
    'durationMs': durationMs,
    'status': status.value,
    'error': error,
    'synced': synced,
  };

  factory SparringRound.fromJson(Map<String, Object?> json) => SparringRound(
    number: (json['number'] as num).toInt(),
    recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? '') ?? DateTime.now(),
    durationMs: (json['durationMs'] as num?)?.toDouble(),
    status: SparringRoundStatus.fromValue(json['status']),
    error: json['error'] as String?,
    synced: json['synced'] == true,
  );
}

/// A sparring session: settings, who's who, and its rounds.
class SparringSession {
  const SparringSession({
    required this.id,
    required this.createdAt,
    this.settings = const SparringSettings(),
    this.partnerName,
    this.youKit,
    this.partnerKit,
    this.identified = false,
    this.templates = const <FighterLabel, IdentityTemplate>{},
    this.rounds = const <SparringRound>[],
  });

  /// Timestamp-based, like the rest of the app's session ids.
  final String id;
  final DateTime createdAt;
  final SparringSettings settings;

  /// Optional, to label the partner and help the AI coach.
  final String? partnerName;

  /// What each fighter is wearing, as typed at setup ("black top, red
  /// shorts"). Optional; helps the AI tell them apart.
  final String? youKit;
  final String? partnerKit;

  /// True once the user has said which fighter they are. From then on every
  /// round is linked against [templates], so **A is the user**.
  final bool identified;

  /// A = the user, B = the partner (once [identified]).
  final Map<FighterLabel, IdentityTemplate> templates;

  final List<SparringRound> rounds;

  /// Display name for a fighter label.
  String nameOf(FighterLabel label) {
    if (!identified) return 'Fighter ${label.letter}';
    if (label == FighterLabel.a) return 'You';
    final name = partnerName?.trim();
    return name == null || name.isEmpty ? 'Partner' : name;
  }

  SparringRound? round(int number) {
    for (final r in rounds) {
      if (r.number == number) return r;
    }
    return null;
  }

  SparringSession withRound(SparringRound round) {
    final next = <SparringRound>[
      for (final r in rounds)
        if (r.number != round.number) r,
      round,
    ]..sort((a, b) => a.number.compareTo(b.number));
    return copyWith(rounds: next);
  }

  SparringSession copyWith({
    SparringSettings? settings,
    String? partnerName,
    String? youKit,
    String? partnerKit,
    bool? identified,
    Map<FighterLabel, IdentityTemplate>? templates,
    List<SparringRound>? rounds,
  }) => SparringSession(
    id: id,
    createdAt: createdAt,
    settings: settings ?? this.settings,
    partnerName: partnerName ?? this.partnerName,
    youKit: youKit ?? this.youKit,
    partnerKit: partnerKit ?? this.partnerKit,
    identified: identified ?? this.identified,
    templates: templates ?? this.templates,
    rounds: rounds ?? this.rounds,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'settings': settings.toJson(),
    'partnerName': partnerName,
    'youKit': youKit,
    'partnerKit': partnerKit,
    'identified': identified,
    'templates': <String, Object?>{
      for (final e in templates.entries) e.key.value: e.value.toJson(),
    },
    'rounds': <Object?>[for (final r in rounds) r.toJson()],
  };

  factory SparringSession.fromJson(Map<String, Object?> json) {
    final templates = (json['templates'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    return SparringSession(
      id: json['id'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      settings: SparringSettings.fromJson(
        (json['settings'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{},
      ),
      partnerName: json['partnerName'] as String?,
      youKit: json['youKit'] as String?,
      partnerKit: json['partnerKit'] as String?,
      identified: json['identified'] == true,
      templates: <FighterLabel, IdentityTemplate>{
        for (final label in FighterLabel.values)
          if (templates[label.value] is Map)
            label: IdentityTemplate.fromJson(
              (templates[label.value] as Map).cast<String, Object?>(),
            ),
      },
      rounds: <SparringRound>[
        for (final r in (json['rounds'] as List<Object?>? ?? const <Object?>[]))
          SparringRound.fromJson((r as Map).cast<String, Object?>()),
      ],
    );
  }
}
