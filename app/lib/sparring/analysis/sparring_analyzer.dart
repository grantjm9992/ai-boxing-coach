import '../ai/sparring_report.dart';
import '../model/fighter.dart';
import '../tracking/fighter_tracker.dart';
import 'fighter_analysis.dart';
import 'interaction.dart';

/// One sparring round, analysed: each fighter, the two together, how much
/// couldn't be resolved, and — when it ran — the AI coach's review.
class SparringRoundAnalysis {
  const SparringRoundAnalysis({
    required this.durationMs,
    required this.fighters,
    required this.interaction,
    required this.unresolvedMs,
    required this.overlapMs,
    required this.analysedAt,
    this.ai,
    this.aiError,
    this.aiStale = false,
    this.version = currentVersion,
  });

  static const int currentVersion = 1;

  final int version;
  final double durationMs;
  final Map<FighterLabel, FighterAnalysis> fighters;
  final InteractionAnalysis interaction;

  /// Per fighter: time not analysed (unresolved, e.g. clinches).
  final Map<FighterLabel, double> unresolvedMs;
  final double overlapMs;
  final DateTime analysedAt;

  /// The AI coach's report, when it ran and parsed.
  final SparringAiReport? ai;

  /// Why the AI review didn't happen or failed, for the UI.
  final String? aiError;

  /// True when who's-who was corrected after the AI review: the review may
  /// describe the wrong fighter in places, so offer to run it again.
  final bool aiStale;

  FighterAnalysis fighter(FighterLabel label) => fighters[label]!;

  SparringRoundAnalysis copyWith({
    Map<FighterLabel, FighterAnalysis>? fighters,
    SparringAiReport? ai,
    String? aiError,
    bool clearAiError = false,
    bool? aiStale,
  }) => SparringRoundAnalysis(
    durationMs: durationMs,
    fighters: fighters ?? this.fighters,
    interaction: interaction,
    unresolvedMs: unresolvedMs,
    overlapMs: overlapMs,
    analysedAt: analysedAt,
    ai: ai ?? this.ai,
    aiError: clearAiError ? null : (aiError ?? this.aiError),
    aiStale: aiStale ?? this.aiStale,
    version: version,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'durationMs': durationMs,
    'fighters': <String, Object?>{
      for (final e in fighters.entries) e.key.value: e.value.toJson(),
    },
    'interaction': interaction.toJson(),
    'unresolvedMs': <String, double>{
      for (final e in unresolvedMs.entries) e.key.value: e.value,
    },
    'overlapMs': overlapMs,
    'analysedAt': analysedAt.toIso8601String(),
    'ai': ai?.toJson(),
    'aiError': aiError,
    'aiStale': aiStale,
  };

  factory SparringRoundAnalysis.fromJson(Map<String, Object?> json) {
    final fighters = (json['fighters'] as Map).cast<String, Object?>();
    final unresolved = (json['unresolvedMs'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    final ai = json['ai'];
    return SparringRoundAnalysis(
      version: (json['version'] as num?)?.toInt() ?? 1,
      durationMs: (json['durationMs'] as num?)?.toDouble() ?? 0,
      fighters: <FighterLabel, FighterAnalysis>{
        for (final label in FighterLabel.values)
          label: FighterAnalysis.fromJson((fighters[label.value] as Map).cast<String, Object?>()),
      },
      interaction: InteractionAnalysis.fromJson(
        (json['interaction'] as Map).cast<String, Object?>(),
      ),
      unresolvedMs: <FighterLabel, double>{
        for (final label in FighterLabel.values)
          label: (unresolved[label.value] as num?)?.toDouble() ?? 0,
      },
      overlapMs: (json['overlapMs'] as num?)?.toDouble() ?? 0,
      analysedAt: DateTime.tryParse(json['analysedAt'] as String? ?? '') ?? DateTime.now(),
      ai: ai is Map ? SparringAiReport.fromJson(ai.cast<String, Object?>()) : null,
      aiError: json['aiError'] as String?,
      aiStale: json['aiStale'] == true,
    );
  }
}

/// Tracked round → [SparringRoundAnalysis] (on-device part).
class SparringAnalyzer {
  const SparringAnalyzer({
    this.fighterAnalyzer = const FighterAnalyzer(),
    this.interactionAnalyzer = const InteractionAnalyzer(),
  });

  final FighterAnalyzer fighterAnalyzer;
  final InteractionAnalyzer interactionAnalyzer;

  SparringRoundAnalysis analyse(
    TrackedRound round, {
    Map<FighterLabel, FighterSetup> setups = const <FighterLabel, FighterSetup>{},
    DateTime? now,
  }) {
    final fighters = <FighterLabel, FighterAnalysis>{
      for (final label in FighterLabel.values)
        label: fighterAnalyzer.analyse(
          round,
          label,
          setup: setups[label] ?? const FighterSetup(),
        ),
    };
    final interaction = interactionAnalyzer.analyse(round, <FighterLabel, List<SparringPunch>>{
      for (final e in fighters.entries) e.key: e.value.punches,
    });
    return SparringRoundAnalysis(
      durationMs: round.durationMs,
      fighters: fighters,
      interaction: interaction,
      unresolvedMs: <FighterLabel, double>{
        for (final label in FighterLabel.values) label: round.unresolvedMs(label),
      },
      overlapMs: round.overlapMs,
      analysedAt: now ?? DateTime.now(),
    );
  }
}
