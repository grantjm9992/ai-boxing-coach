import 'features.dart';
import 'landmarks.dart';
import 'pose.dart';
import 'punch.dart';

/// Combination detection — grouping classified punch events into numbered
/// boxing combinations (brief §7, §9).
///
/// This is a pure function over the [PunchEvent] list the [PunchDetector]
/// already produces: no pose maths of its own, just timing and the numbering
/// map. A run of punches thrown close together in time is one combination;
/// classified types become conventional numbers (1 = jab, 2 = cross, …).

/// The punch-numbering convention (brief §7). Configurable because gyms vary;
/// the number is kept separate from the semantic [PunchType] + hand.
class PunchNumbering {
  const PunchNumbering({
    this.jab = 1,
    this.cross = 2,
    this.leadHook = 3,
    this.rearHook = 4,
    this.leadUppercut = 5,
    this.rearUppercut = 6,
  });

  final int jab;
  final int cross;
  final int leadHook;
  final int rearHook;
  final int leadUppercut;
  final int rearUppercut;

  /// The number for a punch, or `null` when the motion class is unknown and
  /// can't be numbered.
  int? numberFor(PunchType type, {required bool isLead}) => switch (type) {
    PunchType.straight => isLead ? jab : cross,
    PunchType.hook => isLead ? leadHook : rearHook,
    PunchType.uppercut => isLead ? leadUppercut : rearUppercut,
    PunchType.unknown => null,
  };
}

/// Number used in a [Combination.sequence] for a punch we couldn't classify.
const int unknownPunchNumber = 0;

/// One detected combination: a run of punches thrown close together.
class Combination {
  const Combination({
    required this.startMs,
    required this.endMs,
    required this.sequence,
    required this.types,
    required this.confidence,
    required this.punchIndices,
  });

  final double startMs;
  final double endMs;

  /// Conventional numbers, e.g. `[1, 2, 3]`. [unknownPunchNumber] (0) marks a
  /// punch that couldn't be classified.
  final List<int> sequence;

  /// Motion class per punch, index-aligned to [sequence].
  final List<PunchType> types;

  /// 0..1 — the fraction of punches in the run that were classifiable. A run
  /// full of unknowns is a low-confidence combination.
  final double confidence;

  /// Indices into the punch list this combination was built from.
  final List<int> punchIndices;

  int get length => sequence.length;

  /// A compact label like "1-2-3". Unknown punches render as "?".
  String get label => sequence
      .map((n) => n == unknownPunchNumber ? '?' : '$n')
      .join('-');

  Map<String, Object?> toJson() => <String, Object?>{
    'startMs': startMs,
    'endMs': endMs,
    'sequence': sequence,
    'types': types.map((t) => t.value).toList(),
    'confidence': confidence,
    'punchIndices': punchIndices,
  };

  factory Combination.fromJson(Map<String, Object?> json) => Combination(
    startMs: (json['startMs'] as num).toDouble(),
    endMs: (json['endMs'] as num).toDouble(),
    sequence: <int>[
      for (final n in (json['sequence'] as List<Object?>? ?? const []))
        (n as num).toInt(),
    ],
    types: <PunchType>[
      for (final t in (json['types'] as List<Object?>? ?? const []))
        PunchType.values.firstWhere(
          (p) => p.value == t,
          orElse: () => PunchType.unknown,
        ),
    ],
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    punchIndices: <int>[
      for (final i in (json['punchIndices'] as List<Object?>? ?? const []))
        (i as num).toInt(),
    ],
  );
}

/// Groups [punches] (assumed sorted by time) into combinations. Two punches
/// belong to the same combination when the gap from one's end to the next's
/// start is within [maxGapMs]. Runs shorter than two punches are single
/// punches, not combinations, and are not returned.
///
/// [maxGapMs] default is the brief's §9 starting point; tune on real recordings.
List<Combination> detectCombinations(
  PoseSequence sequence,
  List<PunchEvent> punches,
  Stance stance, {
  PunchNumbering numbering = const PunchNumbering(),
  double maxGapMs = 1200,
}) {
  if (punches.length < 2) return const <Combination>[];

  double startMs(PunchEvent p) => sequence.frames[p.startIndex].timestampMs;
  double endMs(PunchEvent p) => sequence.frames[p.endIndex].timestampMs;

  final combos = <Combination>[];
  var runStart = 0; // index into punches where the current run began

  void flush(int endExclusive) {
    final count = endExclusive - runStart;
    if (count >= 2) {
      combos.add(_build(
        sequence,
        punches,
        stance,
        numbering,
        runStart,
        endExclusive,
        startMs,
        endMs,
      ));
    }
  }

  for (var i = 1; i < punches.length; i++) {
    final gap = startMs(punches[i]) - endMs(punches[i - 1]);
    if (gap > maxGapMs) {
      flush(i);
      runStart = i;
    }
  }
  flush(punches.length);
  return combos;
}

Combination _build(
  PoseSequence sequence,
  List<PunchEvent> punches,
  Stance stance,
  PunchNumbering numbering,
  int from,
  int to,
  double Function(PunchEvent) startMs,
  double Function(PunchEvent) endMs,
) {
  final seq = <int>[];
  final types = <PunchType>[];
  final indices = <int>[];
  var known = 0;
  for (var i = from; i < to; i++) {
    final p = punches[i];
    final isLead = p.side == stance.lead;
    final number = numbering.numberFor(p.punchType, isLead: isLead);
    seq.add(number ?? unknownPunchNumber);
    types.add(p.punchType);
    indices.add(i);
    if (number != null) known++;
  }
  return Combination(
    startMs: startMs(punches[from]),
    endMs: endMs(punches[to - 1]),
    sequence: seq,
    types: types,
    confidence: known / (to - from),
    punchIndices: indices,
  );
}
