import 'dart:math' as math;

import '../pose/multi_pose.dart';
import 'appearance.dart';
import 'tracklet.dart';

/// Tuning for [TrackletBuilder]. Distances are in torso-lengths of the body
/// being tracked, so they hold across camera distances.
class TrackletBuilderConfig {
  const TrackletBuilderConfig({
    this.minQuality = 0.45,
    this.overlapIou = 0.3,
    this.maxGapFrames = 6,
    this.gateBase = 0.6,
    this.gatePerFrame = 0.35,
    this.appearanceWeight = 1.0,
    this.scaleWeight = 1.0,
    this.shapeReject = 0.35,
    this.newCost = 1.3,
    this.minMargin = 0.25,
    this.minLength = 3,
    this.maxActive = 6,
  });

  /// Bodies whose shoulders and hips are less visible than this are dropped.
  final double minQuality;

  /// Two bodies whose boxes overlap more than this are not linked at all that
  /// frame — the clinch / crossing case where the detector can merge or swap
  /// limbs. Tracklets near them end.
  final double overlapIou;

  /// A tracklet missing for more than this many frames ends.
  final int maxGapFrames;

  /// How far a body may be from its predicted position and still be linked:
  /// `gateBase + gatePerFrame × frames since last seen`.
  final double gateBase;
  final double gatePerFrame;

  final double appearanceWeight;
  final double scaleWeight;

  /// A body whose limb proportions differ from the tracklet's by more than
  /// this (mean |log ratio|) is a corrupt or merged skeleton: not linked.
  final double shapeReject;

  /// The cost of starting a new tracklet for a body instead of linking it.
  final double newCost;

  /// A link is made only when the next-best assignment costs at least this
  /// much more; otherwise the tracklet ends rather than guess.
  final double minMargin;

  /// Shorter tracklets are dropped as noise.
  final int minLength;

  /// At most this many open tracklets are considered per frame (nearest
  /// first) — bounds the assignment search.
  final int maxActive;
}

/// What [TrackletBuilder.build] produced.
class TrackletBuildResult {
  const TrackletBuildResult({required this.tracklets, required this.overlapFrames});

  /// Every kept tracklet, by start.
  final List<Tracklet> tracklets;

  /// Per frame position: true where bodies overlapped too much to link.
  final List<bool> overlapFrames;
}

/// Links bodies frame to frame into [Tracklet]s — strictly: only while the
/// match is unambiguous. Ending a tracklet costs nothing (the identity linker
/// rejoins tracklets over the whole round); a wrong link would carry one
/// fighter's frames into the other's track. So a tracklet ends on heavy box
/// overlap, a long gap, a corrupt skeleton, or an assignment whose runner-up is
/// nearly as good.
class TrackletBuilder {
  const TrackletBuilder([this.config = const TrackletBuilderConfig()]);

  final TrackletBuilderConfig config;

  TrackletBuildResult build(List<MultiPoseFrame> frames) {
    final cfg = config;
    final kept = <Tracklet>[];
    final overlap = List<bool>.filled(frames.length, false);
    var active = <_Active>[];
    var nextId = 0;

    void close(_Active a) {
      if (a.tracklet.length >= cfg.minLength) kept.add(a.tracklet);
    }

    _Active open(int position, PoseCandidate c) {
      final a = _Active(Tracklet(nextId++));
      a.extend(position, c);
      return a;
    }

    for (var p = 0; p < frames.length; p++) {
      // Close tracklets that have been missing too long.
      final stillOpen = <_Active>[];
      for (final a in active) {
        if (p - a.lastPosition > cfg.maxGapFrames) {
          close(a);
        } else {
          stillOpen.add(a);
        }
      }
      active = stillOpen;

      final usable = <PoseCandidate>[
        for (final c in frames[p].candidates)
          if (c.quality >= cfg.minQuality && c.torso > 0 && c.hip != null) c,
      ];

      // Heavy overlap: those bodies aren't linked, and tracklets heading into
      // them end — after a clinch the linker decides who came out where.
      final overlapped = <int>{};
      for (var i = 0; i < usable.length; i++) {
        for (var j = i + 1; j < usable.length; j++) {
          if (usable[i].box.iou(usable[j].box) > cfg.overlapIou) {
            overlapped..add(i)..add(j);
          }
        }
      }
      if (overlapped.isNotEmpty) {
        overlap[p] = true;
        final survivors = <_Active>[];
        for (final a in active) {
          final near = overlapped.any((i) => a.lastBox.iou(usable[i].box) > 0.05);
          if (near) {
            close(a);
          } else {
            survivors.add(a);
          }
        }
        active = survivors;
      }

      final free = <PoseCandidate>[
        for (var i = 0; i < usable.length; i++)
          if (!overlapped.contains(i)) usable[i],
      ];
      if (free.isEmpty) continue;

      // Bound the search: the open tracklets nearest these bodies.
      var considered = active;
      if (active.length > cfg.maxActive) {
        double nearest(_Active a) => free
            .map((c) => _dist(a.predict(p), c.hip!) / a.scale)
            .reduce(math.min);
        considered = List<_Active>.of(active)
          ..sort((x, y) => nearest(x).compareTo(nearest(y)));
        considered = considered.sublist(0, cfg.maxActive);
      }

      final costs = <List<double>>[
        for (final c in free)
          <double>[for (final a in considered) _pairCost(a, c, p)],
      ];
      final assignments = _enumerate(costs, considered.length, cfg.newCost);
      final best = assignments.reduce((x, y) => x.cost <= y.cost ? x : y);

      final next = <_Active>[...active];
      for (var i = 0; i < free.length; i++) {
        final j = best.choice[i];
        if (j < 0) {
          next.add(open(p, free[i]));
          continue;
        }
        // The cheapest assignment that doesn't make this link.
        var alternative = double.infinity;
        for (final other in assignments) {
          if (other.choice[i] != j && other.cost < alternative) {
            alternative = other.cost;
          }
        }
        final track = considered[j];
        if (alternative - best.cost < cfg.minMargin) {
          // Too close to call: end it and start fresh rather than guess.
          next.remove(track);
          close(track);
          next.add(open(p, free[i]));
        } else {
          track.extend(p, free[i]);
        }
      }
      active = next;
    }
    active.forEach(close);
    kept.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });
    return TrackletBuildResult(tracklets: kept, overlapFrames: overlap);
  }

  double _pairCost(_Active a, PoseCandidate c, int position) {
    final cfg = config;
    final gap = position - a.lastPosition;
    final gate = cfg.gateBase + cfg.gatePerFrame * gap;
    final d = _dist(a.predict(position), c.hip!) / a.scale;
    if (d > gate) return double.infinity;
    final shapeDev = shapeDistance(c.shape, a.shape);
    if (shapeDev.isFinite && shapeDev > cfg.shapeReject) return double.infinity;
    final scaleDev = (math.log(c.torso / a.scale)).abs();
    return d / gate +
        cfg.appearanceWeight * appearanceDistance(c.appearance, a.appearance) +
        cfg.scaleWeight * scaleDev;
  }

  /// Every injective assignment of bodies (rows) to open tracklets (columns),
  /// or to a new tracklet (-1), with finite cost.
  static List<_Assignment> _enumerate(
    List<List<double>> costs,
    int tracks,
    double newCost,
  ) {
    final out = <_Assignment>[];
    final choice = List<int>.filled(costs.length, -1);
    final used = List<bool>.filled(tracks, false);
    void go(int i, double cost) {
      if (i == costs.length) {
        out.add(_Assignment(List<int>.of(choice), cost));
        return;
      }
      choice[i] = -1;
      go(i + 1, cost + newCost);
      for (var j = 0; j < tracks; j++) {
        final c = costs[i][j];
        if (used[j] || !c.isFinite) continue;
        used[j] = true;
        choice[i] = j;
        go(i + 1, cost + c);
        used[j] = false;
      }
      choice[i] = -1;
    }

    go(0, 0);
    return out;
  }

  static double _dist(List<double> a, List<double> b) {
    final dx = a[0] - b[0];
    final dy = a[1] - b[1];
    return math.sqrt(dx * dx + dy * dy);
  }
}

class _Assignment {
  const _Assignment(this.choice, this.cost);
  final List<int> choice;
  final double cost;
}

/// An open tracklet plus the running state used to match it.
class _Active {
  _Active(this.tracklet);

  final Tracklet tracklet;
  int lastPosition = 0;
  List<double> lastHip = const <double>[0, 0];
  PoseBox lastBox = const PoseBox(0, 0, 0, 0);
  List<double> velocity = const <double>[0, 0];
  double scale = 0;
  List<double> appearance = const <double>[];
  List<double> shape = const <double>[];

  static const double _alpha = 0.2;

  void extend(int position, PoseCandidate c) {
    final hip = c.hip!;
    if (tracklet.length > 0) {
      final dt = position - lastPosition;
      if (dt > 0) {
        velocity = <double>[
          (hip[0] - lastHip[0]) / dt,
          (hip[1] - lastHip[1]) / dt,
        ];
      }
      scale = (1 - _alpha) * scale + _alpha * c.torso;
      appearance = _blendAppearance(appearance, c.appearance);
      shape = <double>[
        for (var i = 0; i < c.shape.length; i++)
          i < shape.length && shape[i].isFinite
              ? (c.shape[i].isFinite
                  ? (1 - _alpha) * shape[i] + _alpha * c.shape[i]
                  : shape[i])
              : c.shape[i],
      ];
    } else {
      scale = c.torso;
      appearance = List<double>.of(c.appearance);
      shape = List<double>.of(c.shape);
    }
    tracklet.add(position, c);
    lastPosition = position;
    lastHip = hip;
    lastBox = c.box;
  }

  /// Where the hip should be at [position]: constant velocity, damped (a
  /// boxer's motion reverses constantly).
  List<double> predict(int position) {
    final dt = position - lastPosition;
    return <double>[
      lastHip[0] + 0.5 * velocity[0] * dt,
      lastHip[1] + 0.5 * velocity[1] * dt,
    ];
  }

  static List<double> _blendAppearance(List<double> running, List<double> next) {
    if (running.length != next.length) return List<double>.of(next);
    final out = List<double>.of(running);
    const bins = 11;
    for (var region = 0; region * bins < next.length; region++) {
      final offset = region * bins;
      var seen = 0.0, had = 0.0;
      for (var k = 0; k < bins && offset + k < next.length; k++) {
        seen += next[offset + k];
        had += running[offset + k];
      }
      if (seen <= 0.5) continue; // region not visible this frame
      for (var k = 0; k < bins && offset + k < next.length; k++) {
        out[offset + k] = had <= 0.5
            ? next[offset + k]
            : (1 - _alpha) * running[offset + k] + _alpha * next[offset + k];
      }
    }
    return out;
  }
}
