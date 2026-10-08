import '../../analysis/context.dart';
import '../../analysis/drill.dart';
import '../../analysis/engine.dart';
import '../../analysis/features.dart';
import '../../analysis/landmarks.dart';
import '../../analysis/punch.dart';
import '../../analysis/round_analysis.dart';
import '../../analysis/school.dart';
import '../model/fighter.dart';
import '../tracking/fighter_tracker.dart';
import 'sparring_profile.dart';

/// Findings below this confidence aren't shown (same bar as the single-person
/// Full AI review).
const double kSparringMinConfidence = 0.6;

/// The most findings shown per fighter per round.
const int kSparringMaxFindings = 7;

/// One punch by one fighter, inside a resolved stretch of their track.
class SparringPunch {
  const SparringPunch({
    required this.by,
    required this.side,
    required this.type,
    required this.name,
    required this.startIndex,
    required this.peakIndex,
    required this.endIndex,
    required this.startMs,
    required this.peakMs,
    required this.endMs,
  });

  final FighterLabel by;
  final Side side;
  final PunchType type;

  /// 'jab', 'cross', 'lead hook', …
  final String name;

  /// Frame positions in the round.
  final int startIndex;
  final int peakIndex;
  final int endIndex;

  final double startMs;
  final double peakMs;
  final double endMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'by': by.value,
    'side': side.name,
    'type': type.value,
    'name': name,
    'i': <int>[startIndex, peakIndex, endIndex],
    't': <double>[startMs, peakMs, endMs],
  };

  factory SparringPunch.fromJson(Map<String, Object?> json) {
    final i = (json['i'] as List<Object?>).map((v) => (v as num).toInt()).toList();
    final t = (json['t'] as List<Object?>).map((v) => (v as num).toDouble()).toList();
    return SparringPunch(
      by: FighterLabel.fromValue(json['by']) ?? FighterLabel.a,
      side: json['side'] == 'right' ? Side.right : Side.left,
      type: PunchType.values.firstWhere(
        (p) => p.value == json['type'],
        orElse: () => PunchType.unknown,
      ),
      name: json['name'] as String? ?? 'punch',
      startIndex: i[0],
      peakIndex: i[1],
      endIndex: i[2],
      startMs: t[0],
      peakMs: t[1],
      endMs: t[2],
    );
  }
}

/// One thing to fix (or a positive), for one fighter.
class FighterFinding {
  const FighterFinding({
    required this.code,
    required this.severity,
    required this.confidence,
    required this.text,
    required this.source,
    this.timestampMs,
    this.drill,
  });

  /// Taxonomy code (GUARD_003, …) or 'OTHER'.
  final String code;
  final Severity severity;
  final double confidence;

  /// What was seen and the cue, in the coach's voice.
  final String text;

  /// 'rules' (on-device) or 'ai' (the AI coach).
  final String source;

  /// When it's clearest in the round; null for round-level findings.
  final double? timestampMs;
  final String? drill;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'severity': severity.value,
    'confidence': confidence,
    'text': text,
    'source': source,
    'timestampMs': timestampMs,
    'drill': drill,
  };

  factory FighterFinding.fromJson(Map<String, Object?> json) => FighterFinding(
    code: json['code'] as String? ?? 'OTHER',
    severity: Severity.fromValue(json['severity'] as String? ?? 'minor'),
    confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
    text: json['text'] as String? ?? '',
    source: json['source'] as String? ?? 'rules',
    timestampMs: (json['timestampMs'] as num?)?.toDouble(),
    drill: json['drill'] as String?,
  );
}

/// Everything measured for one fighter in one round.
class FighterAnalysis {
  const FighterAnalysis({
    required this.label,
    required this.stance,
    required this.stanceInferred,
    required this.analysedSeconds,
    required this.punches,
    required this.findings,
    this.strengths = const <String>[],
    this.observations = const <Observation>[],
    this.summary,
    this.note,
  });

  final FighterLabel label;
  final Stance stance;

  /// True when the stance came from the footage rather than the profile.
  final bool stanceInferred;

  /// Seconds of the round in which this fighter was resolved.
  final double analysedSeconds;
  final List<SparringPunch> punches;

  /// Shown corrections: the rules', or the AI coach's once it has reviewed.
  final List<FighterFinding> findings;
  final List<String> strengths;

  /// The rules' raw observations (kept for evaluation and the AI prompt).
  final List<Observation> observations;

  /// The AI coach's read of this fighter's round, when it ran.
  final String? summary;

  /// Why there's little or nothing here (e.g. barely tracked).
  final String? note;

  int get punchCount => punches.length;

  double get punchesPerMinute =>
      analysedSeconds <= 0 ? 0 : punches.length * 60 / analysedSeconds;

  /// Punch counts by name, most thrown first.
  Map<String, int> get punchMix {
    final counts = <String, int>{};
    for (final p in punches) {
      counts[p.name] = (counts[p.name] ?? 0) + 1;
    }
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return <String, int>{for (final e in entries) e.key: e.value};
  }

  FighterAnalysis copyWith({
    List<FighterFinding>? findings,
    List<String>? strengths,
    String? summary,
  }) => FighterAnalysis(
    label: label,
    stance: stance,
    stanceInferred: stanceInferred,
    analysedSeconds: analysedSeconds,
    punches: punches,
    findings: findings ?? this.findings,
    strengths: strengths ?? this.strengths,
    observations: observations,
    summary: summary ?? this.summary,
    note: note,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label.value,
    'stance': stance.name,
    'stanceInferred': stanceInferred,
    'analysedSeconds': analysedSeconds,
    'punches': <Object?>[for (final p in punches) p.toJson()],
    'findings': <Object?>[for (final f in findings) f.toJson()],
    'strengths': strengths,
    'observations': <Object?>[for (final o in observations) o.toJson()],
    'summary': summary,
    'note': note,
  };

  factory FighterAnalysis.fromJson(Map<String, Object?> json) => FighterAnalysis(
    label: FighterLabel.fromValue(json['label']) ?? FighterLabel.a,
    stance: json['stance'] == 'southpaw' ? Stance.southpaw : Stance.orthodox,
    stanceInferred: json['stanceInferred'] == true,
    analysedSeconds: (json['analysedSeconds'] as num?)?.toDouble() ?? 0,
    punches: <SparringPunch>[
      for (final p in (json['punches'] as List<Object?>? ?? const <Object?>[]))
        SparringPunch.fromJson((p as Map).cast<String, Object?>()),
    ],
    findings: <FighterFinding>[
      for (final f in (json['findings'] as List<Object?>? ?? const <Object?>[]))
        FighterFinding.fromJson((f as Map).cast<String, Object?>()),
    ],
    strengths: <String>[
      for (final s in (json['strengths'] as List<Object?>? ?? const <Object?>[]))
        if (s is String) s,
    ],
    observations: <Observation>[
      for (final o in (json['observations'] as List<Object?>? ?? const <Object?>[]))
        Observation.fromJson((o as Map).cast<String, Object?>()),
    ],
    summary: json['summary'] as String?,
    note: json['note'] as String?,
  );
}

/// Who a fighter is for analysis: stance (null = infer it from the footage),
/// guard style and school.
class FighterSetup {
  const FighterSetup({this.stance, this.style = Style.highGuard, this.school});

  final Stance? stance;
  final Style style;
  final School? school;
}

/// Analyses one fighter's track with the existing single-person code, used
/// read-only: their [PoseSequence] (empty frames where unresolved) goes through
/// the unmodified [RuleEngine] with the side-view rule set and a sparring
/// [StyleProfile]. Anything inside or touching an unresolved stretch — a punch,
/// an observation — is dropped, never attributed.
class FighterAnalyzer {
  const FighterAnalyzer();

  /// Frames either side of an unresolved stretch an observation's moment must
  /// clear to be trusted.
  static const int _margin = 5;

  FighterAnalysis analyse(
    TrackedRound round,
    FighterLabel label, {
    FighterSetup setup = const FighterSetup(),
  }) {
    final sequence = round.fighters[label]!;
    final opponent = round.fighters[label.other]!;
    final inferred = setup.stance == null ? inferStance(sequence, opponent) : null;
    final stance = setup.stance ?? inferred ?? Stance.orthodox;
    final resolvedFrames = round.frameCount - _unresolvedFrames(round, label);
    final analysedSeconds = round.fps > 0 ? resolvedFrames / round.fps : 0.0;

    if (resolvedFrames < round.fps * 3) {
      return FighterAnalysis(
        label: label,
        stance: stance,
        stanceInferred: setup.stance == null,
        analysedSeconds: analysedSeconds,
        punches: const <SparringPunch>[],
        findings: const <FighterFinding>[],
        note: 'This fighter was barely tracked this round, so there is nothing '
            'reliable to measure.',
      );
    }

    final context = AnalysisContext(
      sequence: sequence,
      drill: DrillContext(stance: stance, style: setup.style, school: setup.school),
      styleProfile: sparringProfile(style: setup.style, school: setup.school),
    );

    List<PunchEvent> rawPunches;
    List<Observation> observations;
    try {
      rawPunches = context.punches;
      observations = RuleEngine(sparringRules()).run(context);
    } on StateError {
      // No usable torso anywhere: nothing to scale measurements by.
      rawPunches = const <PunchEvent>[];
      observations = const <Observation>[];
    }

    final ranges = round.unresolved[label] ?? const <FrameRange>[];
    bool clean(int from, int to) => !ranges.any((r) => r.overlaps(from, to));

    final punches = <SparringPunch>[
      for (final p in rawPunches)
        if (clean(p.startIndex, p.endIndex))
          SparringPunch(
            by: label,
            side: p.side,
            type: p.punchType,
            name: punchName(p.punchType, p.side, stance),
            startIndex: p.startIndex,
            peakIndex: p.peakIndex,
            endIndex: p.endIndex,
            startMs: round.timestampsMs[p.startIndex],
            peakMs: round.timestampsMs[p.peakIndex],
            endMs: round.timestampsMs[p.endIndex],
          ),
    ];

    final kept = <Observation>[
      for (final o in observations)
        if (o.timestampMs == null ||
            clean(
              _position(round, o.timestampMs!) - _margin,
              _position(round, o.timestampMs!) + _margin,
            ))
          o,
    ];

    return FighterAnalysis(
      label: label,
      stance: stance,
      stanceInferred: setup.stance == null,
      analysedSeconds: analysedSeconds,
      punches: punches,
      findings: findingsFrom(kept),
      strengths: <String>[
        for (final o in kept)
          if (o.severity == Severity.positive) o.coachingText,
      ].take(3).toList(),
      observations: kept,
    );
  }

  /// The rules' confident faults as findings: worst first, one per code,
  /// capped at [kSparringMaxFindings].
  static List<FighterFinding> findingsFrom(List<Observation> observations) {
    final faults = <Observation>[
      for (final o in observations)
        if (o.severity.isFault && o.confidence >= kSparringMinConfidence) o,
    ]..sort((a, b) {
        final bySeverity = b.severity.rank.compareTo(a.severity.rank);
        return bySeverity != 0 ? bySeverity : b.confidence.compareTo(a.confidence);
      });
    final seen = <String>{};
    final out = <FighterFinding>[];
    for (final o in faults) {
      final key = o.code.isEmpty ? o.ruleId : o.code;
      if (!seen.add(key)) continue;
      out.add(FighterFinding(
        code: o.code.isEmpty ? 'OTHER' : o.code,
        severity: o.severity,
        confidence: o.confidence,
        text: o.coachingText,
        source: 'rules',
        timestampMs: o.timestampMs,
      ));
      if (out.length == kSparringMaxFindings) break;
    }
    return out;
  }

  static int _unresolvedFrames(TrackedRound round, FighterLabel label) {
    var n = 0;
    for (final r in round.unresolved[label] ?? const <FrameRange>[]) {
      n += r.length;
    }
    return n;
  }

  /// The frame position nearest [ms].
  static int _position(TrackedRound round, double ms) {
    final t = round.timestampsMs;
    if (t.isEmpty) return 0;
    var lo = 0, hi = t.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (t[mid] < ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0 && (ms - t[lo - 1]).abs() < (t[lo] - ms).abs()) return lo - 1;
    return lo;
  }
}
