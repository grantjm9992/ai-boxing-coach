import '../../analysis/landmarks.dart';
import '../../analysis/pose.dart';
import '../model/fighter.dart';
import '../pose/multi_pose.dart';
import 'identity_linker.dart';
import 'tracklet.dart';
import 'tracklet_builder.dart';

/// How sure the tracker is about one tracklet's label.
enum TrackletStatus {
  /// Clear, or confirmed by the user. Used.
  resolved('resolved'),

  /// Labelled and used, but close enough to call that the user is asked to
  /// check it ("Check who's who").
  review('review'),

  /// Too close to call: **not used** for anything until the user decides.
  excluded('excluded');

  const TrackletStatus(this.value);
  final String value;

  static TrackletStatus fromValue(Object? value) => TrackletStatus.values
      .firstWhere((s) => s.value == value, orElse: () => TrackletStatus.resolved);
}

/// One tracklet's outcome, kept with the round for the review UI and so
/// identity decisions can be re-applied without re-extracting.
class TrackletInfo {
  const TrackletInfo({
    required this.id,
    required this.start,
    required this.end,
    required this.length,
    required this.label,
    required this.margin,
    required this.forced,
    required this.status,
    this.shownAt,
    this.box,
  });

  final int id;
  final int start;
  final int end;
  final int length;

  /// Null = neither fighter.
  final FighterLabel? label;
  final double margin;
  final bool forced;
  final TrackletStatus status;

  /// The frame position to show when asking about it (a member near the
  /// middle), and the body's box there.
  final int? shownAt;
  final PoseBox? box;

  /// The frame to show when asking about it.
  int get middle => shownAt ?? (start + end) ~/ 2;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'start': start,
    'end': end,
    'length': length,
    'label': label?.value,
    'margin': margin.isFinite ? (margin * 1000).round() / 1000 : null,
    'forced': forced,
    'status': status.value,
    'shownAt': shownAt,
    'box': box?.toList().map((v) => (v * 10000).round() / 10000).toList(),
  };

  factory TrackletInfo.fromJson(Map<String, Object?> json) => TrackletInfo(
    id: (json['id'] as num).toInt(),
    start: (json['start'] as num).toInt(),
    end: (json['end'] as num).toInt(),
    length: (json['length'] as num).toInt(),
    label: FighterLabel.fromValue(json['label']),
    margin: (json['margin'] as num?)?.toDouble() ?? double.infinity,
    forced: json['forced'] == true,
    status: TrackletStatus.fromValue(json['status']),
    shownAt: (json['shownAt'] as num?)?.toInt(),
    box: _box(json['box']),
  );

  static PoseBox? _box(Object? raw) {
    if (raw is! List || raw.length != 4) return null;
    final v = <double>[for (final x in raw) (x as num).toDouble()];
    return PoseBox(v[0], v[1], v[2], v[3]);
  }
}

/// Tuning for [FighterTracker] on top of the builder and linker.
class FighterTrackerConfig {
  const FighterTrackerConfig({
    this.builder = const TrackletBuilderConfig(),
    this.linker = const IdentityLinkerConfig(),
    this.excludeBelow = 0.15,
    this.reviewBelow = 0.6,
    this.reviewMinFrames = 20,
    this.referenceMinSwapMargin = 1.0,
  });

  final TrackletBuilderConfig builder;
  final IdentityLinkerConfig linker;

  /// Labelled tracklets with a smaller margin are excluded (not guessed).
  final double excludeBelow;

  /// …and below this, used but put to the user.
  final double reviewBelow;

  /// Tracklets shorter than this aren't worth asking about.
  final int reviewMinFrames;

  /// With a session reference, a round whose labelling beats its A↔B swap by
  /// less than this doesn't clearly match — the user is asked who's who.
  final double referenceMinSwapMargin;
}

/// A round resolved into two fighters.
class TrackedRound {
  const TrackedRound({
    required this.fps,
    required this.timestampsMs,
    required this.tracklets,
    required this.fighters,
    required this.unresolved,
    required this.overlap,
    required this.templates,
    required this.matchedReference,
    required this.swapMargin,
  });

  final double fps;

  /// Every sampled frame's timestamp, by position.
  final List<double> timestampsMs;

  final List<TrackletInfo> tracklets;

  /// One single-person sequence per fighter, aligned to [timestampsMs]: the
  /// fighter's body where resolved, an empty frame where not.
  final Map<FighterLabel, PoseSequence> fighters;

  /// Per fighter: where they weren't resolved (not detected, overlapped, or
  /// in an excluded tracklet). Nothing is measured there.
  final Map<FighterLabel, List<FrameRange>> unresolved;

  /// Where the bodies overlapped too much to link (clinches, crossings).
  final List<FrameRange> overlap;

  final Map<FighterLabel, IdentityTemplate> templates;

  /// True when linked against the session's confirmed fighters (A = user).
  final bool matchedReference;

  /// How clearly the labelling beats swapping A and B everywhere.
  final double swapMargin;

  int get frameCount => timestampsMs.length;

  double get durationMs => timestampsMs.isEmpty ? 0 : timestampsMs.last - timestampsMs.first;

  /// Tracklets the user should look at ("Check who's who").
  List<TrackletInfo> get toReview => <TrackletInfo>[
    for (final t in tracklets)
      if (t.status != TrackletStatus.resolved) t,
  ];

  /// Milliseconds of the round in which [label] wasn't resolved.
  double unresolvedMs(FighterLabel label) {
    final step = fps > 0 ? 1000 / fps : 50.0;
    var frames = 0;
    for (final r in unresolved[label] ?? const <FrameRange>[]) {
      frames += r.length;
    }
    return frames * step;
  }

  double get overlapMs {
    final step = fps > 0 ? 1000 / fps : 50.0;
    var frames = 0;
    for (final r in overlap) {
      frames += r.length;
    }
    return frames * step;
  }

  /// True if [label] is resolved at [position].
  bool isResolved(FighterLabel label, int position) =>
      !(unresolved[label] ?? const <FrameRange>[]).any((r) => r.contains(position));

  /// A frame where both fighters are resolved, well apart and large — the one
  /// to show when asking "which one is you". Null if there's none.
  int? clearestFrame() {
    final a = fighters[FighterLabel.a];
    final b = fighters[FighterLabel.b];
    if (a == null || b == null) return null;
    int? best;
    var bestScore = 0.0;
    for (var p = 0; p < frameCount; p++) {
      if (!isResolved(FighterLabel.a, p) || !isResolved(FighterLabel.b, p)) continue;
      final ca = PoseCandidate(keypoints: a.frames[p].keypoints);
      final cb = PoseCandidate(keypoints: b.frames[p].keypoints);
      if (ca.box.area == 0 || cb.box.area == 0) continue;
      if (ca.box.iou(cb.box) > 0) continue;
      final score = ca.quality + cb.quality + ca.box.height + cb.box.height;
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }
    return best;
  }

  /// The summary that's stored (the sequences are stored separately).
  Map<String, Object?> toJson() => <String, Object?>{
    'fps': fps,
    'timestamps': <double>[for (final t in timestampsMs) (t * 10).round() / 10],
    'tracklets': <Object?>[for (final t in tracklets) t.toJson()],
    'unresolved': <String, Object?>{
      for (final e in unresolved.entries)
        e.key.value: <Object?>[for (final r in e.value) r.toJson()],
    },
    'overlap': <Object?>[for (final r in overlap) r.toJson()],
    'templates': <String, Object?>{
      for (final e in templates.entries) e.key.value: e.value.toJson(),
    },
    'matchedReference': matchedReference,
    'swapMargin': swapMargin.isFinite ? swapMargin : null,
  };

  factory TrackedRound.fromJson(
    Map<String, Object?> json,
    Map<FighterLabel, PoseSequence> fighters,
  ) {
    List<FrameRange> ranges(Object? raw) => <FrameRange>[
      for (final r in (raw as List<Object?>? ?? const <Object?>[]))
        FrameRange.fromJson((r as Map).cast<String, Object?>()),
    ];
    final unresolvedRaw = (json['unresolved'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    final templatesRaw = (json['templates'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    return TrackedRound(
      fps: (json['fps'] as num).toDouble(),
      timestampsMs: <double>[
        for (final t in (json['timestamps'] as List<Object?>)) (t as num).toDouble(),
      ],
      tracklets: <TrackletInfo>[
        for (final t in (json['tracklets'] as List<Object?>? ?? const <Object?>[]))
          TrackletInfo.fromJson((t as Map).cast<String, Object?>()),
      ],
      fighters: fighters,
      unresolved: <FighterLabel, List<FrameRange>>{
        for (final label in FighterLabel.values) label: ranges(unresolvedRaw[label.value]),
      },
      overlap: ranges(json['overlap']),
      templates: <FighterLabel, IdentityTemplate>{
        for (final label in FighterLabel.values)
          if (templatesRaw[label.value] is Map)
            label: IdentityTemplate.fromJson(
              (templatesRaw[label.value] as Map).cast<String, Object?>(),
            ),
      },
      matchedReference: json['matchedReference'] == true,
      swapMargin: (json['swapMargin'] as num?)?.toDouble() ?? double.infinity,
    );
  }
}

/// Multi-pose frames → two fighters. Tracklets first (strict, short), then
/// identities over the whole round, then one single-person [PoseSequence] per
/// fighter so the existing, unmodified analysis code can run on each.
class FighterTracker {
  const FighterTracker([this.config = const FighterTrackerConfig()]);

  final FighterTrackerConfig config;

  /// Tracks [round]. [forced] are the user's identity decisions (tracklet id →
  /// label, null = neither); [reference] the session's confirmed fighters, so
  /// that A is the user.
  TrackedRound track(
    MultiPoseRound round, {
    Map<int, FighterLabel?> forced = const <int, FighterLabel?>{},
    Map<FighterLabel, IdentityTemplate>? reference,
  }) {
    final built = TrackletBuilder(config.builder).build(round.frames);
    final hasReference = reference != null && reference.length == 2;
    final link = IdentityLinker(config.linker).link(
      built.tracklets,
      fps: round.fps,
      forced: forced,
      reference: hasReference ? reference : null,
    );
    return assemble(round, built, link, forced: forced, matchedReference: hasReference);
  }

  /// Builds the [TrackedRound] from a linking result (separate so the
  /// thresholds are testable on their own).
  TrackedRound assemble(
    MultiPoseRound round,
    TrackletBuildResult built,
    LinkResult link, {
    Map<int, FighterLabel?> forced = const <int, FighterLabel?>{},
    bool matchedReference = false,
  }) {
    final n = round.frames.length;
    final infos = <TrackletInfo>[];
    final members = <FighterLabel, List<PoseCandidate?>>{
      for (final label in FighterLabel.values) label: List<PoseCandidate?>.filled(n, null),
    };

    for (final Tracklet t in built.tracklets) {
      final label = link.labels[t.id];
      final margin = link.margins[t.id] ?? double.infinity;
      final isForced = forced.containsKey(t.id);
      var status = TrackletStatus.resolved;
      if (!isForced) {
        if (label != null && margin < config.excludeBelow) {
          status = TrackletStatus.excluded;
        } else if (margin < config.reviewBelow && t.length >= config.reviewMinFrames) {
          status = TrackletStatus.review;
        }
      }
      final shownAt = t.positions[t.positions.length ~/ 2];
      infos.add(TrackletInfo(
        shownAt: shownAt,
        box: t.at(shownAt)?.box,
        id: t.id,
        start: t.start,
        end: t.end,
        length: t.length,
        label: label,
        margin: margin,
        forced: isForced,
        status: status,
      ));
      if (label == null || status == TrackletStatus.excluded) continue;
      final slots = members[label]!;
      for (var k = 0; k < t.positions.length; k++) {
        slots[t.positions[k]] = t.members[k];
      }
    }

    final timestamps = <double>[for (final f in round.frames) f.timestampMs];
    final fighters = <FighterLabel, PoseSequence>{};
    final unresolved = <FighterLabel, List<FrameRange>>{};
    for (final label in FighterLabel.values) {
      final slots = members[label]!;
      fighters[label] = PoseSequence(
        frames: <PoseFrame>[
          for (var p = 0; p < n; p++)
            PoseFrame(
              index: p,
              timestampMs: timestamps[p],
              keypoints: slots[p]?.keypoints ?? const <Landmark, Keypoint>{},
            ),
        ],
        fps: round.fps,
        source: 'sparring/${label.value}',
        meta: <String, Object?>{'fighter': label.value},
      );
      unresolved[label] = FrameRange.fromFlags(<bool>[for (final s in slots) s == null]);
    }

    return TrackedRound(
      fps: round.fps,
      timestampsMs: timestamps,
      tracklets: infos,
      fighters: fighters,
      unresolved: unresolved,
      overlap: FrameRange.fromFlags(built.overlapFrames),
      templates: link.templates,
      matchedReference: matchedReference,
      swapMargin: link.swapMargin,
    );
  }
}
