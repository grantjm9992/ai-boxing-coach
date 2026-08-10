import 'dart:convert';
import 'dart:io';

import 'package:boxing_coach/domain/round_clip.dart';
import 'package:boxing_coach/domain/session_phase.dart';
import 'package:boxing_coach/services/clip_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('clip_store_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  RoundClip clip({
    required String sessionId,
    required int segment,
    required DateTime recordedAt,
    required String path,
  }) => RoundClip(
    sessionId: sessionId,
    segmentIndex: segment,
    phase: SessionPhase.technical,
    path: path,
    recordedAt: recordedAt,
    roundNumber: 1,
    roundsInPhase: 3,
  );

  Future<File> touch(String path) async {
    final file = File(path);
    await file.writeAsBytes(<int>[0, 1, 2]);
    return file;
  }

  test('add then list round-trips a clip', () async {
    final store = ClipStore(baseDir: tempDir);
    final path = await store.allocatePath('s1', 0);
    await touch(path);
    await store.add(
      clip(sessionId: 's1', segment: 0, recordedAt: DateTime(2026, 8, 10), path: path),
    );

    final clips = await store.list();
    expect(clips, hasLength(1));
    expect(clips.single.sessionId, 's1');
    expect(clips.single.path, path);
  });

  test('add replaces a re-recorded segment rather than duplicating it', () async {
    final store = ClipStore(baseDir: tempDir);
    final path = await store.allocatePath('s1', 2);
    await touch(path);
    final first = clip(
      sessionId: 's1',
      segment: 2,
      recordedAt: DateTime(2026, 8, 10, 9),
      path: path,
    );
    await store.add(first);
    await store.add(first.copyWith(durationMs: 42));

    final clips = await store.listForSession('s1');
    expect(clips, hasLength(1));
    expect(clips.single.durationMs, 42);
  });

  test('listForSession returns only that session, ordered by segment', () async {
    final store = ClipStore(baseDir: tempDir);
    for (final entry in <(String, int)>[('s1', 3), ('s2', 0), ('s1', 1)]) {
      final path = await store.allocatePath(entry.$1, entry.$2);
      await touch(path);
      await store.add(
        clip(
          sessionId: entry.$1,
          segment: entry.$2,
          recordedAt: DateTime(2026, 8, 10),
          path: path,
        ),
      );
    }

    final s1 = await store.listForSession('s1');
    expect(s1.map((c) => c.segmentIndex), <int>[1, 3]);
  });

  test('sweepExpired deletes clips older than 7 days and keeps recent ones', () async {
    final now = DateTime(2026, 8, 10, 12);
    final store = ClipStore(baseDir: tempDir, now: () => now);

    final oldPath = await store.allocatePath('old', 0);
    final freshPath = await store.allocatePath('fresh', 0);
    final oldFile = await touch(oldPath);
    await touch(freshPath);

    await store.add(
      clip(
        sessionId: 'old',
        segment: 0,
        recordedAt: now.subtract(const Duration(days: 8)),
        path: oldPath,
      ),
    );
    await store.add(
      clip(
        sessionId: 'fresh',
        segment: 0,
        recordedAt: now.subtract(const Duration(days: 6)),
        path: freshPath,
      ),
    );

    final removed = await store.sweepExpired();

    expect(removed, 1);
    expect(await oldFile.exists(), isFalse, reason: 'expired file is deleted');
    expect(File(freshPath).existsSync(), isTrue, reason: 'recent file is kept');
    final remaining = await store.list();
    expect(remaining.map((c) => c.sessionId), <String>['fresh']);
  });

  test('sweepExpired drops index entries whose file has vanished', () async {
    final now = DateTime(2026, 8, 10, 12);
    final store = ClipStore(baseDir: tempDir, now: () => now);
    final path = await store.allocatePath('ghost', 0);
    // Deliberately do NOT create the file.
    await store.add(
      clip(sessionId: 'ghost', segment: 0, recordedAt: now, path: path),
    );

    final removed = await store.sweepExpired();

    expect(removed, 1);
    expect(await store.list(), isEmpty);
  });

  test('a corrupt index reads as empty rather than throwing', () async {
    final store = ClipStore(baseDir: tempDir);
    final dir = await store.clipsDir();
    await File('${dir.path}/index.json').writeAsString('not json{');

    expect(await store.list(), isEmpty);
    // And it can still be written to afterwards.
    final path = await store.allocatePath('s', 0);
    await touch(path);
    await store.add(
      clip(sessionId: 's', segment: 0, recordedAt: DateTime(2026), path: path),
    );
    expect(await store.list(), hasLength(1));
  });

  test('index survives as valid JSON', () async {
    final store = ClipStore(baseDir: tempDir);
    final path = await store.allocatePath('s', 0);
    await touch(path);
    await store.add(
      clip(sessionId: 's', segment: 0, recordedAt: DateTime(2026), path: path),
    );
    final dir = await store.clipsDir();
    final decoded = jsonDecode(
      await File('${dir.path}/index.json').readAsString(),
    );
    expect(decoded, isA<List<Object?>>());
  });
}
