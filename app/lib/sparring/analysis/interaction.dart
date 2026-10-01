import 'dart:math' as math;

import '../../analysis/landmarks.dart';
import '../../analysis/pose.dart';
import '../model/fighter.dart';
import '../tracking/fighter_tracker.dart';
import 'fighter_analysis.dart';

/// Distance bands, by hip-to-hip distance in torso-lengths. Starting points to
/// calibrate on real footage, not gospel (docs/SPARRING.md).
enum DistanceBand {
  inside('Inside', 'clinch / infighting'),
  mid('Mid range', 'hooks and crosses land'),
  long('Long range', 'jab range and out');

  const DistanceBand(this.label, this.hint);
  final String label;
  final String hint;

  static DistanceBand of(double torsoLengths, {double inside = 2.2, double long = 3.4}) {
    if (torsoLengths < inside) return DistanceBand.inside;
    if (torsoLengths < long) return DistanceBand.mid;
    return DistanceBand.long;
  }
}

/// A burst of punching by either or both fighters.
class Exchange {
  const Exchange({
    required this.startMs,
    required this.endMs,
    required this.startedBy,
    required this.finishedBy,
    required this.punches,
  });

  final double startMs;
  final double endMs;
  final FighterLabel startedBy;
  final FighterLabel finishedBy;

  /// Punches thrown in it, per fighter.
  final Map<FighterLabel, int> punches;

  int get total => punches.values.fold(0, (a, b) => a + b);

  Map<String, Object?> toJson() => <String, Object?>{
    'start': startMs,
    'end': endMs,
    'startedBy': startedBy.value,
    'finishedBy': finishedBy.value,
    'punches': <String, int>{for (final e in punches.entries) e.key.value: e.value},
  };

  factory Exchange.fromJson(Map<String, Object?> json) => Exchange(
    startMs: (json['start'] as num).toDouble(),
    endMs: (json['end'] as num).toDouble(),
    startedBy: FighterLabel.fromValue(json['startedBy']) ?? FighterLabel.a,
    finishedBy: FighterLabel.fromValue(json['finishedBy']) ?? FighterLabel.a,
    punches: <FighterLabel, int>{
      for (final label in FighterLabel.values)
        label: ((json['punches'] as Map?)?[label.value] as num?)?.toInt() ?? 0,
    },
  );
}

/// How a fighter responded to the other's punches, in-plane only (a slip
/// side-on is mostly depth — the AI coach judges that).
class DefenceCounts {
  const DefenceCounts({this.stepBack = 0, this.duck = 0, this.guard = 0, this.none = 0});

  final int stepBack;
  final int duck;
  final int guard;
  final int none;

  int get total => stepBack + duck + guard + none;

  Map<String, Object?> toJson() => <String, Object?>{
    'stepBack': stepBack,
    'duck': duck,
    'guard': guard,
    'none': none,
  };

  factory DefenceCounts.fromJson(Map<String, Object?> json) => DefenceCounts(
    stepBack: (json['stepBack'] as num?)?.toInt() ?? 0,
    duck: (json['duck'] as num?)?.toInt() ?? 0,
    guard: (json['guard'] as num?)?.toInt() ?? 0,
    none: (json['none'] as num?)?.toInt() ?? 0,
  );
}

/// One fighter's side of the interaction.
class FighterInteraction {
  const FighterInteraction({
    this.counters = 0,
    this.guardUnderFire,
    this.landedHeadCandidates = 0,
    this.landedBodyCandidates = 0,
    this.defence = const DefenceCounts(),
    this.exchangesStarted = 0,
  });

  /// Punches thrown within 0.6 s of the other fighter's punch.
  final int counters;

  /// Share (0..1) of the other fighter's punches during which this fighter
  /// kept both hands up. Null when too few to judge.
  final double? guardUnderFire;

  /// Punches whose fist reached the other's head / body in 2D — candidates,
  /// not contact (depth can't be seen).
  final int landedHeadCandidates;
  final int landedBodyCandidates;

  /// Responses to the other fighter's punches.
  final DefenceCounts defence;

  final int exchangesStarted;

  Map<String, Object?> toJson() => <String, Object?>{
    'counters': counters,
    'guardUnderFire': guardUnderFire,
    'landedHead': landedHeadCandidates,
    'landedBody': landedBodyCandidates,
    'defence': defence.toJson(),
    'exchangesStarted': exchangesStarted,
  };

  factory FighterInteraction.fromJson(Map<String, Object?> json) => FighterInteraction(
    counters: (json['counters'] as num?)?.toInt() ?? 0,
    guardUnderFire: (json['guardUnderFire'] as num?)?.toDouble(),
    landedHeadCandidates: (json['landedHead'] as num?)?.toInt() ?? 0,
    landedBodyCandidates: (json['landedBody'] as num?)?.toInt() ?? 0,
    defence: DefenceCounts.fromJson(
      (json['defence'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{},
    ),
    exchangesStarted: (json['exchangesStarted'] as num?)?.toInt() ?? 0,
  );
}

/// Both fighters together: distance, exchanges, counters, guard under fire,
/// defence and landed candidates. Only frames where both are resolved count.
class InteractionAnalysis {
  const InteractionAnalysis({
    required this.analysedSeconds,
    required this.bandSeconds,
    required this.exchanges,
    required this.fighters,
    required this.distanceTimeline,
  });

  /// Seconds in which both fighters were resolved.
  final double analysedSeconds;
  final Map<DistanceBand, double> bandSeconds;
  final List<Exchange> exchanges;
  final Map<FighterLabel, FighterInteraction> fighters;

  /// Hip-to-hip distance in torso-lengths every 0.5 s (null = not resolved).
  final List<double?> distanceTimeline;

  static const double timelineStepMs = 500;

  Map<String, Object?> toJson() => <String, Object?>{
    'analysedSeconds': analysedSeconds,
    'bands': <String, double>{for (final e in bandSeconds.entries) e.key.name: e.value},
    'exchanges': <Object?>[for (final e in exchanges) e.toJson()],
    'fighters': <String, Object?>{
      for (final e in fighters.entries) e.key.value: e.value.toJson(),
    },
    'distance': <double?>[
      for (final d in distanceTimeline) d == null ? null : (d * 100).round() / 100,
    ],
  };

  factory InteractionAnalysis.fromJson(Map<String, Object?> json) {
    final bands = (json['bands'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    final fighters = (json['fighters'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    return InteractionAnalysis(
      analysedSeconds: (json['analysedSeconds'] as num?)?.toDouble() ?? 0,
      bandSeconds: <DistanceBand, double>{
        for (final band in DistanceBand.values)
          band: (bands[band.name] as num?)?.toDouble() ?? 0,
      },
      exchanges: <Exchange>[
        for (final e in (json['exchanges'] as List<Object?>? ?? const <Object?>[]))
          Exchange.fromJson((e as Map).cast<String, Object?>()),
      ],
      fighters: <FighterLabel, FighterInteraction>{
        for (final label in FighterLabel.values)
          label: FighterInteraction.fromJson(
            (fighters[label.value] as Map?)?.cast<String, Object?>() ??
                const <String, Object?>{},
          ),
      },
      distanceTimeline: <double?>[
        for (final d in (json['distance'] as List<Object?>? ?? const <Object?>[]))
          (d as num?)?.toDouble(),
      ],
    );
  }
}

/// Tuning for [InteractionAnalyzer].
class InteractionConfig {
  const InteractionConfig({
    this.insideBelow = 2.2,
    this.longFrom = 3.4,
    this.exchangeGapMs = 1000,
    this.counterWindowMs = 600,
    this.responseWindowMs = 300,
    this.handsUpMargin = 0.1,
    this.handsUpShare = 0.7,
    this.stepBack = 0.3,
    this.duck = 0.25,
    this.headReach = 0.45,
    this.minGuardSamples = 3,
  });

  final double insideBelow;
  final double longFrom;
  final double exchangeGapMs;
  final double counterWindowMs;
  final double responseWindowMs;

  /// Wrists count as "up" when no lower than this (torso-lengths) below the
  /// shoulder line…
  final double handsUpMargin;

  /// …for at least this share of the window.
  final double handsUpShare;

  /// Torso-lengths the hips move away / the head drops for a step-back / duck.
  final double stepBack;
  final double duck;

  /// A fist within this (torso-lengths of the target) of the head is a head
  /// candidate.
  final double headReach;

  final int minGuardSamples;
}

/// Measures the two fighters against each other.
class InteractionAnalyzer {
  const InteractionAnalyzer([this.config = const InteractionConfig()]);

  final InteractionConfig config;

  InteractionAnalysis analyse(
    TrackedRound round,
    Map<FighterLabel, List<SparringPunch>> punches,
  ) {
    final cfg = config;
    final a = round.fighters[FighterLabel.a]!;
    final b = round.fighters[FighterLabel.b]!;
    final n = round.frameCount;
    final step = round.fps > 0 ? 1 / round.fps : 0.05;

    // Distance and bands.
    final distance = List<double?>.filled(n, null);
    final bands = <DistanceBand, double>{for (final band in DistanceBand.values) band: 0};
    var both = 0;
    for (var p = 0; p < n; p++) {
      if (!round.isResolved(FighterLabel.a, p) || !round.isResolved(FighterLabel.b, p)) continue;
      final d = _distance(a.frames[p], b.frames[p]);
      if (d == null) continue;
      distance[p] = d;
      both++;
      final band = DistanceBand.of(d, inside: cfg.insideBelow, long: cfg.longFrom);
      bands[band] = bands[band]! + step;
    }
    final timeline = <double?>[];
    if (n > 0) {
      final start = round.timestampsMs.first;
      for (var t = start; t <= round.timestampsMs.last; t += InteractionAnalysis.timelineStepMs) {
        timeline.add(distance[_nearest(round.timestampsMs, t)]);
      }
    }

    // Exchanges.
    final all = <SparringPunch>[
      ...?punches[FighterLabel.a],
      ...?punches[FighterLabel.b],
    ]..sort((x, y) => x.peakMs.compareTo(y.peakMs));
    final exchanges = <Exchange>[];
    var cluster = <SparringPunch>[];
    void flush() {
      if (cluster.length >= 2) {
        exchanges.add(Exchange(
          startMs: cluster.first.startMs,
          endMs: cluster.last.endMs,
          startedBy: cluster.first.by,
          finishedBy: cluster.last.by,
          punches: <FighterLabel, int>{
            for (final label in FighterLabel.values)
              label: cluster.where((p) => p.by == label).length,
          },
        ));
      }
      cluster = <SparringPunch>[];
    }

    for (final punch in all) {
      if (cluster.isNotEmpty && punch.peakMs - cluster.last.peakMs > cfg.exchangeGapMs) flush();
      cluster.add(punch);
    }
    flush();

    final perFighter = <FighterLabel, FighterInteraction>{};
    for (final label in FighterLabel.values) {
      final own = punches[label] ?? const <SparringPunch>[];
      final theirs = punches[label.other] ?? const <SparringPunch>[];
      final me = round.fighters[label]!;
      final them = round.fighters[label.other]!;

      // Counters: my punch landing within the window after theirs.
      var counters = 0;
      for (final mine in own) {
        final isCounter = theirs.any((t) =>
            mine.peakMs > t.peakMs &&
            mine.peakMs - t.peakMs <= cfg.counterWindowMs &&
            mine.startMs >= t.startMs);
        if (isCounter) counters++;
      }

      // Guard under fire + defence: my response to each of their punches.
      var guardSamples = 0, guardUp = 0;
      var stepBack = 0, duck = 0, guard = 0, none = 0;
      for (final t in theirs) {
        if (!round.isResolved(label, t.startIndex)) continue;
        final windowEnd = _nearest(round.timestampsMs, t.peakMs + cfg.responseWindowMs);
        var upFrames = 0, frames = 0;
        for (var p = t.startIndex; p <= math.min(t.peakIndex, n - 1); p++) {
          if (!round.isResolved(label, p)) continue;
          final up = _handsUp(me.frames[p], cfg.handsUpMargin);
          if (up == null) continue;
          frames++;
          if (up) upFrames++;
        }
        final heldUp = frames > 0 && upFrames / frames >= cfg.handsUpShare;
        if (frames > 0) {
          guardSamples++;
          if (heldUp) guardUp++;
        }

        final response = _response(
          round,
          label,
          me,
          them,
          from: t.startIndex,
          to: windowEnd,
        );
        switch (response) {
          case _Response.duck:
            duck++;
          case _Response.stepBack:
            stepBack++;
          case _Response.none:
            if (heldUp) {
              guard++;
            } else {
              none++;
            }
          case _Response.unknown:
            break;
        }
      }

      // Landed candidates: my fist at peak near their head / inside their torso.
      var head = 0, body = 0;
      for (final mine in own) {
        final p = mine.peakIndex;
        if (!round.isResolved(label.other, p)) continue;
        final fist = me.frames[p].get(mine.side.wrist);
        if (fist == null) continue;
        final target = them.frames[p];
        final torso = _torso(target);
        if (torso == null) continue;
        final nose = target.get(Landmark.nose);
        if (nose != null && _dist(fist.x, fist.y, nose.x, nose.y) < cfg.headReach * torso) {
          head++;
          continue;
        }
        final box = _torsoBox(target, torso);
        if (box != null &&
            fist.x >= box[0] &&
            fist.x <= box[2] &&
            fist.y >= box[1] &&
            fist.y <= box[3]) {
          body++;
        }
      }

      perFighter[label] = FighterInteraction(
        counters: counters,
        guardUnderFire: guardSamples >= cfg.minGuardSamples ? guardUp / guardSamples : null,
        landedHeadCandidates: head,
        landedBodyCandidates: body,
        defence: DefenceCounts(stepBack: stepBack, duck: duck, guard: guard, none: none),
        exchangesStarted: exchanges.where((e) => e.startedBy == label).length,
      );
    }

    return InteractionAnalysis(
      analysedSeconds: both * step,
      bandSeconds: bands,
      exchanges: exchanges,
      fighters: perFighter,
      distanceTimeline: timeline,
    );
  }

  _Response _response(
    TrackedRound round,
    FighterLabel label,
    PoseSequence me,
    PoseSequence them, {
    required int from,
    required int to,
  }) {
    final start = me.frames[from];
    final startHip = _hip(start);
    final startNose = start.get(Landmark.nose);
    final torso = _torso(start);
    final theirHip = _hip(them.frames[from]);
    if (startHip == null || torso == null) return _Response.unknown;
    final away = theirHip == null ? 0.0 : (startHip[0] >= theirHip[0] ? 1.0 : -1.0);
    var maxRetreat = 0.0, maxDrop = 0.0;
    for (var p = from; p <= to && p < me.frames.length; p++) {
      if (!round.isResolved(label, p)) continue;
      final hip = _hip(me.frames[p]);
      if (hip != null && away != 0) {
        maxRetreat = math.max(maxRetreat, (hip[0] - startHip[0]) * away / torso);
      }
      final nose = me.frames[p].get(Landmark.nose);
      if (nose != null && startNose != null) {
        maxDrop = math.max(maxDrop, (nose.y - startNose.y) / torso);
      }
    }
    if (maxDrop >= config.duck) return _Response.duck;
    if (maxRetreat >= config.stepBack) return _Response.stepBack;
    return _Response.none;
  }

  static double? _distance(PoseFrame a, PoseFrame b) {
    final ha = _hip(a), hb = _hip(b);
    final ta = _torso(a), tb = _torso(b);
    if (ha == null || hb == null || ta == null || tb == null) return null;
    return (ha[0] - hb[0]).abs() / ((ta + tb) / 2);
  }

  static List<double>? _hip(PoseFrame f) {
    final l = f.get(Landmark.leftHip), r = f.get(Landmark.rightHip);
    if (l == null || r == null) return null;
    return <double>[(l.x + r.x) / 2, (l.y + r.y) / 2];
  }

  static List<double>? _shoulders(PoseFrame f) {
    final l = f.get(Landmark.leftShoulder), r = f.get(Landmark.rightShoulder);
    if (l == null || r == null) return null;
    return <double>[(l.x + r.x) / 2, (l.y + r.y) / 2];
  }

  static double? _torso(PoseFrame f) {
    final h = _hip(f), s = _shoulders(f);
    if (h == null || s == null) return null;
    final d = _dist(h[0], h[1], s[0], s[1]);
    return d > 0 ? d : null;
  }

  /// [x0, y0, x1, y1] around the torso, widened a little (side-on the torso
  /// is narrow).
  static List<double>? _torsoBox(PoseFrame f, double torso) {
    final h = _hip(f), s = _shoulders(f);
    if (h == null || s == null) return null;
    final cx = (h[0] + s[0]) / 2;
    final half = 0.25 * torso;
    return <double>[cx - half, math.min(s[1], h[1]), cx + half, math.max(s[1], h[1])];
  }

  /// Both wrists no lower than [margin] torso-lengths below the shoulder line.
  /// Null when the wrists or shoulders aren't there.
  static bool? _handsUp(PoseFrame f, double margin) {
    final s = _shoulders(f);
    final torso = _torso(f);
    final l = f.get(Landmark.leftWrist), r = f.get(Landmark.rightWrist);
    if (s == null || torso == null || l == null || r == null) return null;
    final line = s[1] + margin * torso;
    return l.y <= line && r.y <= line;
  }

  static double _dist(double x0, double y0, double x1, double y1) {
    final dx = x0 - x1, dy = y0 - y1;
    return math.sqrt(dx * dx + dy * dy);
  }

  static int _nearest(List<double> timestamps, double ms) {
    if (timestamps.isEmpty) return 0;
    var lo = 0, hi = timestamps.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (timestamps[mid] < ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0 && (ms - timestamps[lo - 1]).abs() < (timestamps[lo] - ms).abs()) return lo - 1;
    return lo;
  }
}

enum _Response { duck, stepBack, none, unknown }
