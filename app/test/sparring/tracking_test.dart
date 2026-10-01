import 'dart:math' as math;

import 'package:boxing_coach/sparring/model/fighter.dart';
import 'package:boxing_coach/sparring/pose/multi_pose.dart';
import 'package:boxing_coach/sparring/tracking/appearance.dart';
import 'package:boxing_coach/sparring/tracking/fighter_tracker.dart';
import 'package:boxing_coach/sparring/tracking/tracklet_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'synthetic.dart';

const Person red = Person(1, topBin: 8, shortsBin: 0); // black top, red shorts
const Person blue = Person(2, topBin: 10, shortsBin: 5); // white top, blue shorts

/// Two fighters circling: [a] starts on the left facing right. Between
/// [crossFrom] and [crossTo] they pass each other (one in front of the other,
/// so their boxes overlap) and finish on swapped sides.
MultiPoseRound circling(
  Person a,
  Person b, {
  int frames = 240,
  int? crossFrom,
  int? crossTo,
  List<PoseCandidate> Function(int frame)? extra,
  int seed = 1,
}) {
  final rnd = math.Random(seed);
  final perFrame = <List<PoseCandidate>>[];
  for (var i = 0; i < frames; i++) {
    final sway = 0.04 * math.sin(i / 9);
    double ax = 0.33 + sway, bx = 0.67 - sway;
    if (crossFrom != null && crossTo != null) {
      if (i >= crossTo) {
        ax = 0.67 - sway;
        bx = 0.33 + sway;
      } else if (i >= crossFrom) {
        final k = (i - crossFrom) / (crossTo - crossFrom);
        ax = 0.33 + 0.34 * k;
        bx = 0.67 - 0.34 * k;
      }
    }
    final aFacing = ax < bx ? 1 : -1;
    perFrame.add(<PoseCandidate>[
      body(a, x: ax, y: 0.62, facing: aFacing, leadReach: i % 23 == 0 ? 1 : 0, jitter: rnd),
      body(b, x: bx, y: 0.6, facing: -aFacing, rearReach: i % 31 == 0 ? 1 : 0, jitter: rnd),
      ...?extra?.call(i),
    ]);
  }
  return roundOf(perFrame, seed: seed);
}

void main() {
  group('appearance', () {
    test('identical kits are 0 apart, different kits 1, unseen is neutral', () {
      final x = body(red, x: 0.3).appearance;
      final y = body(blue, x: 0.6).appearance;
      expect(appearanceDistance(x, x), closeTo(0, 1e-9));
      expect(appearanceDistance(x, y), closeTo(1, 1e-9));
      expect(appearanceDistance(x, List<double>.filled(22, 0)), kNeutralAppearanceDistance);
    });

    test('names the dominant colours', () {
      final app = body(blue, x: 0.3).appearance;
      expect(dominantColourName(app, shorts: false), 'white');
      expect(dominantColourName(app, shorts: true), 'blue');
    });
  });

  group('candidate features', () {
    test('facing, scale and shape come from the skeleton', () {
      final right = body(red, x: 0.3, facing: 1);
      final left = body(red, x: 0.3, facing: -1);
      expect(right.facing, 1);
      expect(left.facing, -1);
      expect(right.torso, closeTo(red.scale, 0.01));
      expect(right.shape[1], closeTo(red.forearm, 0.05));
    });

    test('round-trips through JSON', () {
      final c = body(blue, x: 0.4, leadReach: 1);
      final back = PoseCandidate.fromJson(c.toJson());
      expect(back.box.x0, closeTo(c.box.x0, 1e-3));
      expect(back.appearance, c.appearance);
      expect(back.facing, c.facing);
    });
  });

  group('TrackletBuilder', () {
    test('two fighters apart make two long tracklets', () {
      final result = const TrackletBuilder().build(circling(red, blue).frames);
      final long = result.tracklets.where((t) => t.length > 200).toList();
      expect(long, hasLength(2));
      expect(result.overlapFrames.where((o) => o), isEmpty);
    });

    test('overlapping bodies end tracklets instead of guessing', () {
      final result = const TrackletBuilder()
          .build(circling(red, blue, crossFrom: 100, crossTo: 140).frames);
      expect(result.overlapFrames.where((o) => o), isNotEmpty);
      // No tracklet holds both people.
      for (final t in result.tracklets) {
        final people = <int?>{for (final m in t.members) truth[m.keypoints]};
        expect(people, hasLength(1), reason: 'tracklet ${t.id} mixes people');
      }
    });
  });

  group('FighterTracker', () {
    test('resolves two fighters with no switches; A starts on the left', () {
      final tracked = const FighterTracker().track(circling(red, blue));
      final score = scoreIdentity(tracked);
      expect(score.wrong, 0);
      expect(score.person[FighterLabel.a], red.id);
      expect(score.person[FighterLabel.b], blue.id);
      expect(score.unresolved, lessThan(tracked.frameCount * 2 * 0.05));
      expect(tracked.toReview, isEmpty);
    });

    test('keeps identity through a crossing (fighters swap sides)', () {
      final tracked = const FighterTracker()
          .track(circling(red, blue, crossFrom: 100, crossTo: 140));
      final score = scoreIdentity(tracked);
      expect(score.wrong, 0);
      expect(score.person[FighterLabel.a], red.id);
      expect(score.person[FighterLabel.b], blue.id);
      // After the crossing, A (red) is on the right.
      final after = tracked.fighters[FighterLabel.a]!.frames[200];
      expect(personAt(tracked, FighterLabel.a, 200), red.id);
      expect(PoseCandidate(keypoints: after.keypoints).hip![0], greaterThan(0.5));
      expect(tracked.overlap, isNotEmpty);
    });

    test('a clinch is left unresolved, then re-linked by kit', () {
      final rnd = math.Random(3);
      final perFrame = <List<PoseCandidate>>[];
      for (var i = 0; i < 200; i++) {
        if (i >= 80 && i < 110) {
          // Clinch: tangled together in the middle; red spins them round.
          perFrame.add(<PoseCandidate>[
            body(red, x: 0.49, facing: 1, jitter: rnd),
            body(blue, x: 0.51, facing: -1, jitter: rnd),
          ]);
        } else {
          final redLeft = i < 80;
          perFrame.add(<PoseCandidate>[
            body(red, x: redLeft ? 0.35 : 0.65, facing: redLeft ? 1 : -1, jitter: rnd),
            body(blue, x: redLeft ? 0.65 : 0.35, facing: redLeft ? -1 : 1, jitter: rnd),
          ]);
        }
      }
      final tracked = const FighterTracker().track(roundOf(perFrame));
      final score = scoreIdentity(tracked);
      expect(score.wrong, 0);
      expect(score.person[FighterLabel.a], red.id);
      // The clinch itself isn't attributed to anyone.
      for (var p = 82; p < 108; p++) {
        expect(tracked.isResolved(FighterLabel.a, p), isFalse);
        expect(tracked.isResolved(FighterLabel.b, p), isFalse);
      }
      expect(personAt(tracked, FighterLabel.a, 150), red.id);
      expect(tracked.unresolvedMs(FighterLabel.a), greaterThan(1000));
    });

    test('same kit: body shape carries identity through a crossing', () {
      const lanky = Person(1, topBin: 8, shortsBin: 8, forearm: 0.78, shin: 0.95);
      const stocky = Person(2, topBin: 8, shortsBin: 8, forearm: 0.5, shin: 0.68);
      final tracked = const FighterTracker()
          .track(circling(lanky, stocky, crossFrom: 100, crossTo: 140));
      final score = scoreIdentity(tracked);
      expect(score.wrong, 0);
      expect(score.person[FighterLabel.a], isNot(score.person[FighterLabel.b]));
    });

    test('a bystander in the background is neither fighter', () {
      const coach = Person(3, topBin: 3, shortsBin: 9, scale: 0.09);
      final tracked = const FighterTracker().track(circling(
        red,
        blue,
        extra: (i) => <PoseCandidate>[body(coach, x: 0.88, y: 0.4, facing: -1)],
      ));
      final score = scoreIdentity(tracked);
      expect(score.wrong, 0);
      expect(<int?>{score.person[FighterLabel.a], score.person[FighterLabel.b]},
          <int?>{red.id, blue.id});
    });

    test("a session reference keeps A = the user even when they start on the right", () {
      final first = const FighterTracker().track(circling(red, blue));
      // Round 2: blue starts on the left.
      final second = const FighterTracker().track(
        circling(blue, red, seed: 5),
        reference: first.templates,
      );
      expect(second.matchedReference, isTrue);
      final score = scoreIdentity(second);
      expect(score.wrong, 0);
      expect(score.person[FighterLabel.a], red.id);
      expect(second.swapMargin, greaterThan(1));
    });

    test("a forced label (the user's swap) is applied and marked resolved", () {
      final round = circling(red, blue);
      final first = const FighterTracker().track(round);
      final longest = first.tracklets.reduce((x, y) => x.length >= y.length ? x : y);
      final flipped = const FighterTracker().track(
        round,
        forced: <int, FighterLabel?>{longest.id: longest.label!.other},
      );
      final info = flipped.tracklets.firstWhere((t) => t.id == longest.id);
      expect(info.label, longest.label!.other);
      expect(info.forced, isTrue);
      expect(info.status, TrackletStatus.resolved);
    });

    test('TrackedRound summary round-trips through JSON', () {
      final tracked = const FighterTracker()
          .track(circling(red, blue, crossFrom: 100, crossTo: 140));
      final back = TrackedRound.fromJson(tracked.toJson(), tracked.fighters);
      expect(back.tracklets.length, tracked.tracklets.length);
      expect(back.unresolvedMs(FighterLabel.a), tracked.unresolvedMs(FighterLabel.a));
      expect(back.overlap.length, tracked.overlap.length);
      expect(back.templates.keys, tracked.templates.keys);
    });

    test('clearestFrame finds a frame with both fighters apart', () {
      final tracked = const FighterTracker().track(circling(red, blue));
      final p = tracked.clearestFrame();
      expect(p, isNotNull);
      expect(tracked.isResolved(FighterLabel.a, p!), isTrue);
      expect(tracked.isResolved(FighterLabel.b, p), isTrue);
    });
  });
}
