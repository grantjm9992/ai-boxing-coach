import 'dart:io';

import 'package:boxing_coach/domain/round_clip.dart';
import 'package:boxing_coach/domain/session_phase.dart';
import 'package:boxing_coach/services/sync/backfill_queue.dart';
import 'package:boxing_coach/services/sync/round_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [RoundSync] that returns a canned outcome and records what it was asked to
/// do — no Supabase.
class FakeRoundSync implements RoundSync {
  FakeRoundSync(this.outcome);

  SyncOutcome outcome;
  final List<RoundClip> synced = <RoundClip>[];
  final List<String> finalized = <String>[];

  @override
  Future<SyncOutcome> syncRound(
    RoundClip clip, {
    String? title,
    String? mode,
  }) async {
    synced.add(clip);
    return outcome;
  }

  @override
  Future<SyncOutcome> finalizeSession(
    String clientSessionId, {
    DateTime? endedAt,
    String? title,
    Map<String, Object?>? rollup,
  }) async {
    finalized.add(clientSessionId);
    return outcome;
  }
}

void main() {
  late Directory tempDir;
  late File file;

  RoundClip clip(int segment, {DateTime? recordedAt}) => RoundClip(
    sessionId: 's1',
    segmentIndex: segment,
    phase: SessionPhase.technical,
    path: '/clips/s1_seg$segment.mp4',
    recordedAt: recordedAt ?? DateTime.now(),
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backfill_test');
    file = File('${tempDir.path}/sync_queue.json');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('a round that uploads is drained and removed', () async {
    final sync = FakeRoundSync(const SyncOutcome(SyncStatus.uploaded));
    final queue = BackfillQueue(sync: sync, file: file);

    await queue.enqueueRound(clip(0), title: 'Drill', mode: 'keyframe');
    expect(queue.pending, 1);

    await queue.process();

    expect(sync.synced, hasLength(1));
    expect(queue.pending, 0);
  });

  test('a failed round is kept for a later attempt', () async {
    final sync = FakeRoundSync(SyncOutcome(SyncStatus.failed, error: 'boom'));
    final queue = BackfillQueue(sync: sync, file: file);

    await queue.enqueueRound(clip(0));
    await queue.process();

    expect(sync.synced, hasLength(1));
    expect(queue.pending, 1); // still queued

    // Next trigger, now online, drains it.
    sync.outcome = const SyncOutcome(SyncStatus.uploaded);
    await queue.process();
    expect(queue.pending, 0);
  });

  test('signed out halts the drain and holds every job', () async {
    final sync = FakeRoundSync(const SyncOutcome(SyncStatus.skippedSignedOut));
    final queue = BackfillQueue(sync: sync, file: file);

    await queue.enqueueRound(clip(0));
    await queue.enqueueRound(clip(1));
    await queue.process();

    // Stopped after the first job; nothing lost.
    expect(sync.synced, hasLength(1));
    expect(queue.pending, 2);
  });

  test('re-enqueuing the same round replaces rather than duplicates', () async {
    final sync = FakeRoundSync(SyncOutcome(SyncStatus.failed, error: 'x'));
    final queue = BackfillQueue(sync: sync, file: file);

    await queue.enqueueRound(clip(0), mode: 'keyframe');
    await queue.enqueueRound(clip(0), mode: 'offline');
    expect(queue.pending, 1);
  });

  test('jobs survive a restart (new queue, same file)', () async {
    final first = BackfillQueue(
      sync: FakeRoundSync(const SyncOutcome(SyncStatus.skippedSignedOut)),
      file: file,
    );
    await first.enqueueRound(clip(0));
    await first.process(); // held (signed out)

    // Simulate a relaunch: a fresh queue on the same file, now online.
    final sync = FakeRoundSync(const SyncOutcome(SyncStatus.uploaded));
    final second = BackfillQueue(sync: sync, file: file);
    await second.process();

    expect(sync.synced, hasLength(1));
    expect(second.pending, 0);
  });

  test('a stale round (past retention) is dropped without a sync attempt',
      () async {
    final sync = FakeRoundSync(const SyncOutcome(SyncStatus.uploaded));
    final queue = BackfillQueue(sync: sync, file: file);

    await queue.enqueueRound(
      clip(0, recordedAt: DateTime.now().subtract(const Duration(days: 30))),
    );
    await queue.process();

    expect(sync.synced, isEmpty); // never attempted
    expect(queue.pending, 0); // dropped
  });

  test('no analysis (swept) is treated as terminal and dropped', () async {
    final sync = FakeRoundSync(const SyncOutcome(SyncStatus.skippedNoAnalysis));
    final queue = BackfillQueue(sync: sync, file: file);

    await queue.enqueueRound(clip(0));
    await queue.process();

    expect(queue.pending, 0);
  });
}
