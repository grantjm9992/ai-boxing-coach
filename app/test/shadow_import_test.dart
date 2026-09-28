import 'dart:io';

import 'package:boxing_coach/domain/imported_round.dart';
import 'package:boxing_coach/domain/session_phase.dart';
import 'package:boxing_coach/domain/shadow_round.dart';
import 'package:boxing_coach/services/clip_store.dart';
import 'package:boxing_coach/services/video_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// Importing an already-filmed video as a shadow round: what's accepted, and
/// that an accepted file lands in the clip store exactly as a recorded round
/// does (so the analysis pipeline, review screen and sync see no difference).
void main() {
  group('import bounds', () {
    test('a normal round is accepted and keeps its measured length', () {
      final check = checkImportedVideo(const Duration(minutes: 2, seconds: 13));
      expect(check, isA<ImportOk>());
      expect((check as ImportOk).duration,
          const Duration(minutes: 2, seconds: 13));
    });

    test('the bounds themselves are inclusive', () {
      expect(checkImportedVideo(kMinImportedRound), isA<ImportOk>());
      expect(checkImportedVideo(kMaxImportedRound), isA<ImportOk>());
    });

    test('an unreadable file is rejected rather than imported', () {
      // Null means the probe couldn't decode it — the pose estimator won't
      // either, so importing would only produce a round that fails to analyse.
      expect(checkImportedVideo(null), isA<ImportRejected>());
      expect(checkImportedVideo(Duration.zero), isA<ImportRejected>());
    });

    test('too short is rejected, and says how short', () {
      final check = checkImportedVideo(const Duration(seconds: 4));
      expect(check, isA<ImportRejected>());
      expect((check as ImportRejected).message, contains('4 seconds'));
    });

    test('too long is rejected, and names the limit', () {
      final check = checkImportedVideo(const Duration(minutes: 12));
      expect(check, isA<ImportRejected>());
      final message = (check as ImportRejected).message;
      expect(message, contains('12 minutes'));
      expect(message, contains('5 minutes'));
    });
  });

  group('PickedVideo.extension', () {
    PickedVideo at(String path) => PickedVideo(path: path, name: 'clip');

    test('keeps a real video extension so the AI upload types it right', () {
      // A .mov filed as .mp4 would be uploaded to Full AI review under the
      // wrong mime type (see VideoVisionRequest.mimeType).
      expect(at('/tmp/a.mov').extension, 'mov');
      expect(at('/tmp/a.MP4').extension, 'mp4');
      expect(at('/tmp/a.mkv').extension, 'mkv');
    });

    test('falls back to mp4 when the name carries nothing usable', () {
      expect(at('/tmp/no_extension').extension, 'mp4');
      expect(at('/tmp/trailing.').extension, 'mp4');
      expect(at('/tmp/weird.this-is-not-an-ext').extension, 'mp4');
    });
  });

  group('fileImportedClip', () {
    late Directory dir;
    late ClipStore clips;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('shadow_import');
      clips = ClipStore(baseDir: dir);
    });
    tearDown(() => dir.delete(recursive: true));

    Future<PickedVideo> pickedFile(String name) async {
      final source = File('${dir.path}/$name');
      await source.writeAsBytes(<int>[0, 1, 2, 3]);
      return PickedVideo(path: source.path, name: name);
    }

    test('files the video as round 1 of the session and indexes it', () async {
      final at = DateTime(2026, 9, 28, 9);
      final clip = await fileImportedClip(
        await pickedFile('round.mp4'),
        clips: clips,
        sessionId: 'shadow_99',
        durationMs: 125000,
        at: at,
      );

      expect(clip, isNotNull);
      expect(clip!.sessionId, 'shadow_99');
      expect(clip.segmentIndex, 0);
      expect(clip.roundNumber, 1);
      expect(clip.phase, SessionPhase.shadow);
      expect(clip.durationMs, 125000);
      // recordedAt is the import moment, so the 7-day sweep starts now rather
      // than whenever the video was originally filmed.
      expect(clip.recordedAt, at);
      expect(File(clip.path).existsSync(), isTrue);

      // Indexed, so the review screen and the retention sweep can find it.
      final listed = await clips.listForSession('shadow_99');
      expect(listed.single.path, clip.path);
    });

    test('the filed clip keeps the source extension', () async {
      final clip = await fileImportedClip(
        await pickedFile('iphone.mov'),
        clips: clips,
        sessionId: 'shadow_100',
        durationMs: 60000,
        at: DateTime(2026, 9, 28),
      );
      expect(clip!.path, endsWith('.mov'));
    });

    test('returns null when the source is gone rather than half-filing', () async {
      final clip = await fileImportedClip(
        const PickedVideo(path: '/nope/missing.mp4', name: 'missing.mp4'),
        clips: clips,
        sessionId: 'shadow_101',
        durationMs: 60000,
        at: DateTime(2026, 9, 28),
      );
      expect(clip, isNull);
      expect(await clips.listForSession('shadow_101'), isEmpty);
    });
  });

  test('an imported round is labelled as imported in History', () {
    final record = shadowSessionRecord(
      null,
      durationMs: 90000,
      sessionId: 'shadow_102',
      completedAt: DateTime(2026, 9, 28),
      templateName: 'Shadow boxing (imported)',
      roundTitle: 'Imported round',
    );
    expect(record.templateName, 'Shadow boxing (imported)');
    expect(record.rounds.single.title, 'Imported round');
    // Still attributed to the same skills as a recorded shadow round.
    expect(record.workSeconds, 90);
    expect(record.categorySeconds, isNotEmpty);
  });

  test('the picker double reports whether it was opened', () async {
    final picker = FakeVideoPicker(
      const PickedVideo(path: '/tmp/x.mp4', name: 'x.mp4'),
    );
    expect(picker.calls, 0);
    expect((await picker.pickFromGallery())?.name, 'x.mp4');
    expect(picker.calls, 1);

    final cancelled = FakeVideoPicker(null);
    expect(await cancelled.pickFromGallery(), isNull);
  });
}
