import 'dart:io';

import 'package:boxing_coach/data/session_templates.dart';
import 'package:boxing_coach/domain/session_phase.dart';
import 'package:boxing_coach/domain/session_plan.dart';
import 'package:boxing_coach/domain/session_settings.dart';
import 'package:boxing_coach/engine/session_plan_builder.dart';
import 'package:boxing_coach/services/clip_store.dart';
import 'package:boxing_coach/services/round_recorder.dart';
import 'package:boxing_coach/services/round_recording_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const template = SessionTemplates.balancedFull;
  final plan = SessionPlanBuilder.build(
    template,
    SessionSettings.fromTemplate(template),
  );

  final SessionSegment technical = plan.segments.firstWhere(
    (s) => s.phase == SessionPhase.technical && s.isWork,
  );
  final SessionSegment nonRecordable = plan.segments.firstWhere(
    (s) => !shouldRecordSegment(s),
  );

  group('shouldRecordSegment', () {
    test('is true only for technical work rounds', () {
      expect(shouldRecordSegment(technical), isTrue);

      final technicalRest = plan.segments.firstWhere(
        (s) => s.phase == SessionPhase.technical && s.isRest,
        orElse: () => nonRecordable,
      );
      expect(shouldRecordSegment(technicalRest), isFalse);

      final warmUp = plan.segments.firstWhere(
        (s) => s.phase == SessionPhase.warmUp,
      );
      expect(shouldRecordSegment(warmUp), isFalse);
      expect(shouldRecordSegment(null), isFalse);
    });
  });

  group('RoundRecordingController', () {
    late Directory tempDir;
    late ClipStore store;
    late FakeRoundRecorder recorder;
    late RoundRecordingController controller;
    late DateTime clock;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('recorder_test');
      store = ClipStore(baseDir: tempDir);
      recorder = FakeRoundRecorder(tempPath: '${tempDir.path}/temp.mp4');
      await recorder.initialize(); // stands in for the camera check
      clock = DateTime(2026, 8, 10, 12);
      controller = RoundRecordingController(
        recorder: recorder,
        clipStore: store,
        sessionId: 'sess',
        now: () => clock,
      );
    });

    /// A round long enough to clear [RoundRecordingController.minClipDuration].
    void elapseARound() => clock = clock.add(const Duration(minutes: 2));

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<void> writeTempClip() =>
        File(recorder.tempPath).writeAsBytes(<int>[0, 1, 2]);

    test('records only on entering a technical round, files it on leaving', () async {
      await controller.onSegment(nonRecordable);
      expect(controller.isRecording, isFalse);

      await controller.onSegment(technical);
      expect(controller.isRecording, isTrue);
      expect(recorder.isRecording, isTrue);

      await writeTempClip();
      elapseARound();
      await controller.onSegment(nonRecordable);

      expect(controller.isRecording, isFalse);
      final clips = await store.listForSession('sess');
      expect(clips, hasLength(1));
      expect(clips.single.segmentIndex, technical.index);
      expect(clips.single.phase, SessionPhase.technical);
      expect(File(clips.single.path).existsSync(), isTrue);
      // The temp file was moved, not copied.
      expect(File(recorder.tempPath).existsSync(), isFalse);
    });

    test('a too-short recording (skipped round) is discarded, not filed', () async {
      await controller.onSegment(technical);
      await writeTempClip();
      // No clock advance: the "round" lasted milliseconds, as when skipping.
      await controller.onSegment(nonRecordable);

      expect(await store.listForSession('sess'), isEmpty);
      // The stray temp file is cleaned up rather than left on disk.
      expect(File(recorder.tempPath).existsSync(), isFalse);
    });

    test('calling onSegment repeatedly with the same segment does not restart', () async {
      await controller.onSegment(technical);
      final startCount = recorder.events.where((e) => e == 'start').length;
      await controller.onSegment(technical);
      expect(recorder.events.where((e) => e == 'start').length, startCount);
    });

    test('finish() files a round still in progress', () async {
      await controller.onSegment(technical);
      await writeTempClip();
      elapseARound();

      await controller.finish();

      expect(controller.isRecording, isFalse);
      expect(await store.listForSession('sess'), hasLength(1));
    });

    test('an unavailable camera degrades to no recording, no throw', () async {
      final broken = FakeRoundRecorder(available: false);
      final c = RoundRecordingController(
        recorder: broken,
        clipStore: store,
        sessionId: 'sess2',
      );

      await c.onSegment(technical); // must not throw
      expect(c.isRecording, isFalse);

      await c.onSegment(nonRecordable);
      expect(await store.listForSession('sess2'), isEmpty);
    });
  });
}
