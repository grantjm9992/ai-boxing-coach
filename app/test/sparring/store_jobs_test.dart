import 'dart:io';
import 'dart:math' as math;

import 'package:boxing_coach/domain/user_profile.dart';
import 'package:boxing_coach/services/ai/video_vision_model.dart';
import 'package:boxing_coach/sparring/ai/sparring_coach.dart';
import 'package:boxing_coach/sparring/data/sparring_store.dart';
import 'package:boxing_coach/sparring/data/sparring_sync.dart';
import 'package:boxing_coach/sparring/jobs/sparring_jobs.dart';
import 'package:boxing_coach/sparring/model/fighter.dart';
import 'package:boxing_coach/sparring/model/sparring_session.dart';
import 'package:boxing_coach/sparring/pose/multi_pose.dart';
import 'package:boxing_coach/sparring/pose/sparring_pose_service.dart';
import 'package:boxing_coach/sparring/tracking/fighter_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sparring_pose/sparring_pose.dart';

import 'synthetic.dart';

const Person red = Person(1, topBin: 8, shortsBin: 0);
const Person blue = Person(2, topBin: 10, shortsBin: 5);

/// Red on the left (or right when [swapSides]) jabbing; blue the other side.
MultiPoseRound round({bool swapSides = false, int frames = 120}) {
  final rnd = math.Random(4);
  return roundOf(<List<PoseCandidate>>[
    for (var i = 0; i < frames; i++)
      <PoseCandidate>[
        body(red, x: swapSides ? 0.75 : 0.25, facing: swapSides ? -1 : 1,
            leadReach: i % 30 < 5 ? <double>[0.35, 0.8, 1, 0.8, 0.35][i % 30] : 0, jitter: rnd),
        body(blue, x: swapSides ? 0.25 : 0.75, facing: swapSides ? 1 : -1, jitter: rnd),
      ],
  ]);
}

class _FakePose implements SparringPoseSource {
  _FakePose(this.rounds);
  final Map<String, MultiPoseRound> rounds;
  final List<String> calls = <String>[];

  @override
  Future<MultiPoseRound> extract(String videoPath, {void Function(double fraction)? onProgress}) async {
    calls.add(videoPath);
    onProgress?.call(0.5);
    for (final e in rounds.entries) {
      if (videoPath.contains(e.key)) return e.value;
    }
    throw const SparringPoseException('no such clip');
  }
}

class _FakeUploader implements SparringUploader {
  final List<String> uploads = <String>[];
  @override
  Future<bool> upload(String sessionId, int round) async {
    uploads.add('$sessionId#$round');
    return true;
  }
}

const String _report = '{"summary":"s","fighter_a":{"summary":"A read","strengths":[],'
    '"priority_issues":[{"code":"GUARD_002","severity":"HIGH","confidence":0.9,'
    '"timestamps":[2],"observation":"Rear hand low","correction":"Hand up."}]},'
    '"fighter_b":{"summary":"B read","strengths":[],"priority_issues":[]}}';

void main() {
  late Directory dir;
  late SparringStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = await Directory.systemTemp.createTemp('sparring_test');
    store = SparringStore(baseDir: dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('SparringStore', () {
    test('sessions, frames, tracking, decisions and analysis round-trip', () async {
      final session = SparringSession(id: 'spar-1', createdAt: DateTime(2026, 10, 1))
          .withRound(SparringRound(number: 1, recordedAt: DateTime(2026, 10, 1, 10)));
      await store.saveSession(session);
      expect((await store.loadSession('spar-1'))!.rounds.single.number, 1);
      expect((await store.listSessions()).single.id, 'spar-1');

      final frames = round();
      await store.saveFrames('spar-1', 1, frames);
      final back = (await store.loadFrames('spar-1', 1))!;
      expect(back.frames.length, frames.frames.length);
      expect(back.frames.first.candidates.length, 2);

      final tracked = const FighterTracker().track(back);
      await store.saveTracked('spar-1', 1, tracked);
      final trackedBack = (await store.loadTracked('spar-1', 1))!;
      expect(trackedBack.fighters[FighterLabel.a]!.length, tracked.frameCount);
      expect(trackedBack.tracklets.length, tracked.tracklets.length);

      await store.saveDecisions('spar-1', 1, <int, FighterLabel?>{3: FighterLabel.b, 4: null});
      final decisions = await store.loadDecisions('spar-1', 1);
      expect(decisions[3], FighterLabel.b);
      expect(decisions.containsKey(4), isTrue);
      expect(decisions[4], isNull);
    });

    test('NaN never breaks a save', () {
      expect(jsonSafe(<String, Object?>{'x': double.nan, 'y': <Object?>[1.0, double.infinity]}),
          <String, Object?>{'x': null, 'y': <Object?>[1.0, null]});
    });

    test('sweeps clips past retention, keeps everything else', () async {
      final old = SparringStore(baseDir: dir, now: () => DateTime.now().add(const Duration(days: 8)));
      final clip = File(await store.clipPath('spar-2', 1));
      await clip.writeAsString('video');
      await store.saveFrames('spar-2', 1, round(frames: 5));
      expect(await old.sweepExpiredClips(), 1);
      expect(await clip.exists(), isFalse);
      expect(await store.loadFrames('spar-2', 1), isNotNull);
    });
  });

  group('SparringJobs', () {
    late _FakePose pose;
    late _FakeUploader uploader;

    SparringJobs jobs({String? aiResponse}) => SparringJobs(
      store: store,
      poseSource: pose,
      coach: () => aiResponse == null
          ? null
          : SparringCoach(model: FakeVideoVisionModel(response: aiResponse)),
      profile: () async => const UserProfile(),
      sync: SparringSyncQueue.forTesting(uploader),
    );

    Future<void> record(String sessionId, int number, {bool ai = true}) async {
      final existing = await store.loadSession(sessionId) ??
          SparringSession(
            id: sessionId,
            createdAt: DateTime(2026, 10, 1),
            settings: SparringSettings(aiReview: ai),
          );
      await store.saveSession(existing.withRound(SparringRound(number: number, recordedAt: DateTime.now())));
      await File(await store.clipPath(sessionId, number)).writeAsString('video');
    }

    setUp(() {
      pose = _FakePose(<String, MultiPoseRound>{
        '/r1/': round(),
        '/r2/': round(swapSides: true),
      });
      uploader = _FakeUploader();
    });

    test('a recorded round is extracted, tracked, measured, reviewed and synced', () async {
      final j = jobs(aiResponse: _report);
      await record('s', 1);
      j.enqueueRound('s', 1);
      await j.idle;
      await SparringSyncQueue.forTesting(uploader).process();

      final session = (await store.loadSession('s'))!;
      expect(session.round(1)!.status, SparringRoundStatus.done);
      final analysis = (await store.loadAnalysis('s', 1))!;
      expect(analysis.ai, isNotNull);
      expect(analysis.fighter(FighterLabel.a).findings.single.code, 'GUARD_002');
      expect(analysis.fighter(FighterLabel.a).punchCount, greaterThan(0));
      expect(await store.loadFrames('s', 1), isNotNull);
      expect(uploader.uploads, contains('s#1'));
      expect(j.progress.value, isEmpty);
    });

    test('without the AI coach the round keeps its on-device analysis', () async {
      final j = jobs();
      await record('s', 1);
      j.enqueueRound('s', 1);
      await j.idle;
      final analysis = (await store.loadAnalysis('s', 1))!;
      expect(analysis.ai, isNull);
      expect(analysis.aiError, isNotNull);
      expect((await store.loadSession('s'))!.round(1)!.status, SparringRoundStatus.done);
    });

    test('a failed extraction marks the round failed with the reason', () async {
      final j = jobs();
      await record('s', 3); // no frames for r3
      j.enqueueRound('s', 3);
      await j.idle;
      final r = (await store.loadSession('s'))!.round(3)!;
      expect(r.status, SparringRoundStatus.failed);
      expect(r.error, contains('no such clip'));
    });

    test('"which one is you": A becomes the user in every round, AI swapped to match', () async {
      final j = jobs(aiResponse: _report);
      await record('s', 1);
      await record('s', 2);
      j.enqueueRound('s', 1);
      j.enqueueRound('s', 2);
      await j.idle;
      // Round 1: red started left → A = red. The user is blue (B).
      await j.identify('s', 1, FighterLabel.b);
      await j.idle;

      final session = (await store.loadSession('s'))!;
      expect(session.identified, isTrue);
      for (final n in <int>[1, 2]) {
        final tracked = (await store.loadTracked('s', n))!;
        // Blue is the user: in round 1 blue is on the right, in round 2 left.
        final hip = PoseCandidate(keypoints: tracked.fighters[FighterLabel.a]!.frames[10].keypoints).hip!;
        expect(hip[0], n == 1 ? greaterThan(0.5) : lessThan(0.5), reason: 'round $n');
        expect(tracked.matchedReference, isTrue);
      }
      final r1 = (await store.loadAnalysis('s', 1))!;
      // The AI's "fighter_a" was red; after the swap it describes B.
      expect(r1.fighter(FighterLabel.b).findings.single.code, 'GUARD_002');
      expect(r1.fighter(FighterLabel.a).findings, isEmpty);
      expect(r1.aiStale, isFalse);
    });

    test("a user's swap re-tracks from stored frames, without re-extracting", () async {
      final j = jobs(aiResponse: _report);
      await record('s', 1);
      j.enqueueRound('s', 1);
      await j.idle;
      final calls = pose.calls.length;
      final tracked = (await store.loadTracked('s', 1))!;
      final longest = tracked.tracklets.reduce((x, y) => x.length >= y.length ? x : y);
      await j.decide('s', 1, longest.id, longest.label!.other);
      await j.idle;
      expect(pose.calls.length, calls);
      final after = (await store.loadTracked('s', 1))!;
      expect(after.tracklets.firstWhere((t) => t.id == longest.id).label, longest.label!.other);
      // A swap moves the partner too: the two fighters trade labels, and the
      // AI review follows rather than going stale.
      final analysis = (await store.loadAnalysis('s', 1))!;
      expect(analysis.aiStale, isFalse);
      expect(analysis.fighter(FighterLabel.b).findings.single.code, 'GUARD_002');
    });
  });

  test('compareLabels tells same, swapped and changed apart', () {
    final r = round();
    final a = const FighterTracker().track(r);
    expect(compareLabels(a, a), LabelMapping.same);
    final longest = a.tracklets.reduce((x, y) => x.length >= y.length ? x : y);
    // Force the two long tracklets the other way round: a full swap.
    final other = a.tracklets.firstWhere((t) => t.id != longest.id && t.label != null);
    final b = const FighterTracker().track(r, forced: <int, FighterLabel?>{
      longest.id: longest.label!.other,
      other.id: other.label!.other,
    });
    expect(compareLabels(a, b), LabelMapping.swapped);
  });
}
