import 'dart:math' as math;

import '../model/fighter.dart';
import 'appearance.dart';
import 'tracklet.dart';

/// What a fighter looks like, for linking: kit colours, body proportions and
/// size in frame. Built from a round's labelled tracklets; once the user has
/// said which fighter they are, the session keeps theirs and their partner's
/// so later rounds are linked against them (A = the user, every round).
class IdentityTemplate {
  const IdentityTemplate({
    required this.appearance,
    required this.shape,
    required this.scale,
  });

  final List<double> appearance;
  final List<double> shape;
  final double scale;

  /// Length-weighted over [tracklets]; null when there are none.
  static IdentityTemplate? fromTracklets(Iterable<Tracklet> tracklets) {
    final list = tracklets.toList();
    if (list.isEmpty) return null;
    final appearances = <List<double>>[];
    final shapes = <List<double>>[];
    final scales = <double>[];
    for (final t in list) {
      // Weight by length without letting one huge tracklet swamp the rest.
      final copies = math.max(1, math.min(t.length, 200) ~/ 20);
      for (var i = 0; i < copies; i++) {
        appearances.add(t.appearance);
        shapes.add(t.shape);
        if (t.scale.isFinite) scales.add(t.scale);
      }
    }
    return IdentityTemplate(
      appearance: meanAppearance(appearances),
      shape: medianShape(shapes),
      scale: median(scales),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'appearance': <double>[for (final v in appearance) _r(v)],
    'shape': <double?>[for (final v in shape) v.isFinite ? _r(v) : null],
    'scale': scale.isFinite ? _r(scale) : null,
  };

  factory IdentityTemplate.fromJson(Map<String, Object?> json) => IdentityTemplate(
    appearance: <double>[
      for (final v in (json['appearance'] as List<Object?>? ?? const <Object?>[]))
        (v as num).toDouble(),
    ],
    shape: <double>[
      for (final v in (json['shape'] as List<Object?>? ?? const <Object?>[]))
        v is num ? v.toDouble() : double.nan,
    ],
    scale: (json['scale'] as num?)?.toDouble() ?? double.nan,
  );

  static double _r(double v) => (v * 10000).round() / 10000;
}

/// Tuning for [IdentityLinker].
class IdentityLinkerConfig {
  const IdentityLinkerConfig({
    this.minLength = 5,
    this.otherCost = 0.75,
    this.appearanceWeight = 1.0,
    this.shapeWeight = 4.0,
    this.scaleWeight = 0.5,
    this.continuityWeight = 0.6,
    this.continuityBase = 0.5,
    this.speedPerSecond = 4.0,
    this.weightUnit = 20,
    this.weightCap = 60,
    this.iterations = 3,
    this.maxStates = 256,
  });

  /// Shorter tracklets are left unlabelled.
  final int minLength;

  /// Per unit of weight: what calling a tracklet "neither fighter" costs. A
  /// bystander's tracklet looks like neither template and lands here.
  final double otherCost;

  final double appearanceWeight;

  /// Shape distances are small numbers (~0.1 for a clearly different build).
  final double shapeWeight;

  /// Low: size in frame changes as fighters move towards / away from the lens.
  final double scaleWeight;

  /// Cost of a jump between consecutive tracklets of one fighter, per unit of
  /// "further than they could have moved".
  final double continuityWeight;

  /// Torso-lengths a fighter may be from where they were last seen, plus
  /// [speedPerSecond] for each second of the gap.
  final double continuityBase;
  final double speedPerSecond;

  /// A tracklet's weight is `min(length, weightCap) / weightUnit` frames, so
  /// long tracklets count for more, up to a point.
  final int weightUnit;
  final int weightCap;

  /// Template ↔ labelling refinement passes when there's no reference.
  final int iterations;

  /// Cap on distinct DP states per step (exact below it).
  final int maxStates;
}

/// The labelling [IdentityLinker.link] chose, and how sure it is.
class LinkResult {
  const LinkResult({
    required this.labels,
    required this.margins,
    required this.templates,
    required this.swapMargin,
  });

  /// Label per tracklet id; null = neither fighter (bystander or noise).
  final Map<int, FighterLabel?> labels;

  /// Per tracklet id: how much worse the best labelling is with this tracklet
  /// labelled differently. Large = sure; near 0 = a coin toss.
  final Map<int, double> margins;

  /// Each fighter's template as linked (from the reference when given).
  final Map<FighterLabel, IdentityTemplate> templates;

  /// How much worse it would be to swap A and B everywhere. With a reference,
  /// small means this round doesn't clearly match the session's fighters.
  final double swapMargin;
}

/// Labels every tracklet of a round A, B or neither, over the **whole round**
/// at once — the payoff of analysing a recording: frames after a crossing or a
/// clinch decide who came out where as much as frames before it.
///
/// Costs combine appearance (kit colours), body shape and size against each
/// fighter's template, plus continuity between one fighter's consecutive
/// tracklets; tracklets that co-occur can't share a label. With two labels the
/// state is just "each fighter's latest tracklet", so a dynamic programme over
/// tracklets in start order finds the best labelling exactly (bounded by
/// [IdentityLinkerConfig.maxStates]). Each tracklet's margin is the cost of the
/// best labelling that disagrees with it.
class IdentityLinker {
  const IdentityLinker([this.config = const IdentityLinkerConfig()]);

  final IdentityLinkerConfig config;

  LinkResult link(
    List<Tracklet> tracklets, {
    required double fps,
    Map<int, FighterLabel?> forced = const <int, FighterLabel?>{},
    Map<FighterLabel, IdentityTemplate>? reference,
  }) {
    final cfg = config;
    final ordered = <Tracklet>[
      for (final t in tracklets)
        if (t.length >= cfg.minLength || forced.containsKey(t.id)) t,
    ]..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    final labels = <int, FighterLabel?>{
      for (final t in tracklets) t.id: null,
    };
    if (ordered.isEmpty) {
      return LinkResult(
        labels: labels,
        margins: const <int, double>{},
        templates: reference ?? const <FighterLabel, IdentityTemplate>{},
        swapMargin: 0,
      );
    }

    var templates = <FighterLabel, IdentityTemplate>{};
    if (reference != null && reference.length == 2) {
      templates = Map<FighterLabel, IdentityTemplate>.of(reference);
    } else {
      templates = _seedTemplates(ordered, forced);
    }

    final continuity = _ContinuityCache(cfg, fps);
    var problem = _Problem(ordered, templates, cfg, continuity, forced);
    var best = problem.solve(const <int, int>{});
    final passes = reference != null && reference.length == 2 ? 1 : cfg.iterations;
    for (var pass = 1; pass < passes; pass++) {
      final refined = <FighterLabel, IdentityTemplate>{};
      for (final label in FighterLabel.values) {
        final template = IdentityTemplate.fromTracklets(<Tracklet>[
          for (var i = 0; i < ordered.length; i++)
            if (best.choice[i] == label.index) ordered[i],
        ]);
        if (template != null) refined[label] = template;
      }
      if (refined.length < 2) break;
      templates = refined;
      problem = _Problem(ordered, templates, cfg, continuity, forced);
      best = problem.solve(const <int, int>{});
    }

    var choice = best.choice;
    // Without a reference A is whoever is on the left when both are first
    // seen together; keep that convention stable.
    if (reference == null || reference.length < 2) {
      if (_aStartsOnRight(ordered, choice)) {
        choice = <int>[for (final c in choice) c < 0 ? c : 1 - c];
        templates = <FighterLabel, IdentityTemplate>{
          if (templates[FighterLabel.b] != null) FighterLabel.a: templates[FighterLabel.b]!,
          if (templates[FighterLabel.a] != null) FighterLabel.b: templates[FighterLabel.a]!,
        };
        problem = _Problem(ordered, templates, cfg, continuity, forced);
      }
    }
    final bestCost = problem.cost(choice);

    final margins = <int, double>{};
    for (var i = 0; i < ordered.length; i++) {
      final id = ordered[i].id;
      if (forced.containsKey(id)) {
        margins[id] = double.infinity;
        continue;
      }
      var alternative = double.infinity;
      for (final option in const <int>[0, 1, -1]) {
        if (option == choice[i]) continue;
        final alt = problem.solve(<int, int>{i: option});
        alternative = math.min(alternative, alt.cost);
      }
      margins[id] = alternative - bestCost;
    }

    for (var i = 0; i < ordered.length; i++) {
      labels[ordered[i].id] = choice[i] < 0 ? null : FighterLabel.values[choice[i]];
    }
    final swapped = <int>[for (final c in choice) c < 0 ? c : 1 - c];
    return LinkResult(
      labels: labels,
      margins: margins,
      templates: templates,
      swapMargin: problem.cost(swapped) - bestCost,
    );
  }

  /// Seeds from the pair of tracklets that are together longest — two bodies
  /// on screen at once are two different people — favouring the biggest (the
  /// fighters are nearest the camera). The left one is A.
  ///
  /// The user's decisions win: a seed they've labelled the other way swaps
  /// the seeds, and their labelled tracklets join that fighter's template.
  Map<FighterLabel, IdentityTemplate> _seedTemplates(
    List<Tracklet> ordered,
    Map<int, FighterLabel?> forced,
  ) {
    Tracklet? bestA, bestB;
    var bestScore = 0.0;
    for (var i = 0; i < ordered.length; i++) {
      for (var j = i + 1; j < ordered.length; j++) {
        final x = ordered[i], y = ordered[j];
        final together = math.min(x.end, y.end) - math.max(x.start, y.start) + 1;
        if (together <= 0) continue;
        final size = (x.scale.isFinite ? x.scale : 0.0) + (y.scale.isFinite ? y.scale : 0.0);
        final score = together * size;
        if (score > bestScore) {
          bestScore = score;
          final xLeft = x.meanX <= y.meanX;
          bestA = xLeft ? x : y;
          bestB = xLeft ? y : x;
        }
      }
    }
    if (bestA == null || bestB == null) {
      final byLength = List<Tracklet>.of(ordered)
        ..sort((a, b) => b.length.compareTo(a.length));
      bestA = byLength.first;
      bestB = byLength.length > 1 ? byLength[1] : null;
    }
    if (forced[bestA.id] == FighterLabel.b ||
        (bestB != null && forced[bestB.id] == FighterLabel.a)) {
      if (bestB != null) {
        final swap = bestA;
        bestA = bestB;
        bestB = swap;
      }
    }
    List<Tracklet> seedsFor(FighterLabel label, Tracklet? seed) => <Tracklet>[
      if (seed != null && (!forced.containsKey(seed.id) || forced[seed.id] == label)) seed,
      for (final t in ordered)
        if (forced[t.id] == label && t != seed) t,
    ];
    final a = IdentityTemplate.fromTracklets(seedsFor(FighterLabel.a, bestA));
    final b = IdentityTemplate.fromTracklets(seedsFor(FighterLabel.b, bestB));
    return <FighterLabel, IdentityTemplate>{
      FighterLabel.a: ?a,
      FighterLabel.b: ?b,
    };
  }

  /// True when, at the first frame both labelled fighters are present, A's hip
  /// is to the right of B's.
  static bool _aStartsOnRight(List<Tracklet> ordered, List<int> choice) {
    final a = <Tracklet>[for (var i = 0; i < ordered.length; i++) if (choice[i] == 0) ordered[i]];
    final b = <Tracklet>[for (var i = 0; i < ordered.length; i++) if (choice[i] == 1) ordered[i]];
    for (final ta in a) {
      for (final tb in b) {
        if (!ta.overlapsInTime(tb)) continue;
        final from = math.max(ta.start, tb.start);
        final to = math.min(ta.end, tb.end);
        for (var p = from; p <= to; p++) {
          final ca = ta.at(p), cb = tb.at(p);
          final ha = ca?.hip, hb = cb?.hip;
          if (ha != null && hb != null) return ha[0] > hb[0];
        }
      }
    }
    return false;
  }
}

/// Pairwise continuity costs, cached across DP runs.
class _ContinuityCache {
  _ContinuityCache(this.cfg, this.fps);

  final IdentityLinkerConfig cfg;
  final double fps;
  final Map<int, double> _cache = <int, double>{};

  double between(Tracklet prev, Tracklet next) {
    final key = prev.id * 100000 + next.id;
    return _cache[key] ??= _compute(prev, next);
  }

  double _compute(Tracklet prev, Tracklet next) {
    final from = prev.endHip;
    final to = next.startHip;
    if (from == null || to == null) return 0;
    final scales = <double>[
      if (prev.scale.isFinite) prev.scale,
      if (next.scale.isFinite) next.scale,
    ];
    if (scales.isEmpty) return 0;
    final scale = scales.reduce((a, b) => a + b) / scales.length;
    final dx = from[0] - to[0], dy = from[1] - to[1];
    final displacement = math.sqrt(dx * dx + dy * dy) / scale;
    final seconds = math.max(0, next.start - prev.end) / (fps <= 0 ? 20 : fps);
    final allowed = cfg.continuityBase + cfg.speedPerSecond * seconds;
    return cfg.continuityWeight * math.min(3.0, displacement / allowed);
  }
}

class _Solution {
  const _Solution(this.choice, this.cost);
  final List<int> choice; // per ordered tracklet: 0 = A, 1 = B, -1 = neither
  final double cost;
}

class _Node {
  const _Node(this.choice, this.parent);
  final int choice;
  final _Node? parent;
}

class _State {
  _State(this.lastA, this.lastB, this.cost, this.path);
  final int lastA;
  final int lastB;
  final double cost;
  final _Node? path;
}

/// One labelling problem: fixed tracklets, templates and forced labels.
class _Problem {
  _Problem(this.ordered, this.templates, this.cfg, this.continuity, Map<int, FighterLabel?> forced)
    : _forced = <int, int>{
        for (var i = 0; i < ordered.length; i++)
          if (forced.containsKey(ordered[i].id))
            i: forced[ordered[i].id]?.index ?? -1,
      } {
    _unary = <List<double>>[
      for (final t in ordered)
        <double>[_unaryCost(t, FighterLabel.a), _unaryCost(t, FighterLabel.b), _otherCost(t)],
    ];
  }

  final List<Tracklet> ordered;
  final Map<FighterLabel, IdentityTemplate> templates;
  final IdentityLinkerConfig cfg;
  final _ContinuityCache continuity;
  final Map<int, int> _forced;
  late final List<List<double>> _unary;

  double _weight(Tracklet t) => math.min(t.length, cfg.weightCap) / cfg.weightUnit;

  double _otherCost(Tracklet t) => cfg.otherCost * _weight(t);

  double _unaryCost(Tracklet t, FighterLabel label) {
    final template = templates[label];
    if (template == null) return 0.5 * _weight(t);
    final app = appearanceDistance(t.appearance, template.appearance);
    final shapeD = shapeDistance(t.shape, template.shape);
    final scaleD = t.scale.isFinite && template.scale.isFinite && template.scale > 0
        ? math.log(t.scale / template.scale).abs()
        : 0.0;
    final cost = cfg.appearanceWeight * app +
        cfg.shapeWeight * (shapeD.isFinite ? shapeD : 0.05) +
        cfg.scaleWeight * scaleD;
    return cost * _weight(t);
  }

  /// The total cost of a full labelling (for comparing, e.g. a swap).
  double cost(List<int> choice) {
    var total = 0.0;
    final last = <int>[-1, -1];
    for (var i = 0; i < ordered.length; i++) {
      final c = choice[i];
      if (c < 0) {
        total += _unary[i][2];
        continue;
      }
      if (last[c] >= 0) {
        if (ordered[last[c]].end >= ordered[i].start) return double.infinity;
        total += continuity.between(ordered[last[c]], ordered[i]);
      }
      total += _unary[i][c];
      last[c] = i;
    }
    return total;
  }

  /// The cheapest labelling, honouring the forced labels plus [extra] (index
  /// in [ordered] → 0 / 1 / -1).
  _Solution solve(Map<int, int> extra) {
    var states = <int, _State>{_key(-1, -1): _State(-1, -1, 0, null)};
    for (var i = 0; i < ordered.length; i++) {
      final t = ordered[i];
      final fixed = extra[i] ?? _forced[i];
      final next = <int, _State>{};
      void offer(_State s) {
        final key = _key(s.lastA, s.lastB);
        final existing = next[key];
        if (existing == null || s.cost < existing.cost) next[key] = s;
      }

      for (final s in states.values) {
        for (final option in const <int>[0, 1, -1]) {
          if (fixed != null && option != fixed) continue;
          if (option < 0) {
            offer(_State(s.lastA, s.lastB, s.cost + _unary[i][2], _Node(-1, s.path)));
            continue;
          }
          final last = option == 0 ? s.lastA : s.lastB;
          var cost = s.cost + _unary[i][option];
          if (last >= 0) {
            final prev = ordered[last];
            if (prev.end >= t.start) continue; // one fighter can't be in two places
            cost += continuity.between(prev, t);
          }
          offer(_State(
            option == 0 ? i : s.lastA,
            option == 1 ? i : s.lastB,
            cost,
            _Node(option, s.path),
          ));
        }
      }
      if (next.isEmpty) {
        // Constraints can't be met (contradictory forced labels): drop this
        // tracklet rather than fail the round.
        for (final s in states.values) {
          offer(_State(s.lastA, s.lastB, s.cost + _unary[i][2], _Node(-1, s.path)));
        }
      }
      if (next.length > cfg.maxStates) {
        final sorted = next.values.toList()..sort((a, b) => a.cost.compareTo(b.cost));
        states = <int, _State>{
          for (final s in sorted.take(cfg.maxStates)) _key(s.lastA, s.lastB): s,
        };
      } else {
        states = next;
      }
    }
    final best = states.values.reduce((a, b) => a.cost <= b.cost ? a : b);
    final choice = List<int>.filled(ordered.length, -1);
    var node = best.path;
    for (var i = ordered.length - 1; i >= 0 && node != null; i--) {
      choice[i] = node.choice;
      node = node.parent;
    }
    return _Solution(choice, best.cost);
  }

  static int _key(int a, int b) => (a + 1) * 1000003 + (b + 1);
}
