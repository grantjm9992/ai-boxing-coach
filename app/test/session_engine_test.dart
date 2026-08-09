import 'package:boxing_coach/data/session_templates.dart';
import 'package:boxing_coach/domain/session_phase.dart';
import 'package:boxing_coach/domain/session_plan.dart';
import 'package:boxing_coach/domain/session_settings.dart';
import 'package:boxing_coach/engine/coach_cue.dart';
import 'package:boxing_coach/engine/session_engine.dart';
import 'package:boxing_coach/engine/session_plan_builder.dart';
import 'package:boxing_coach/services/coach_voice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SilentCoachVoice voice;
  late SessionPlan plan;
  late SessionEngine engine;

  /// A short session, so a test can run the whole thing.
  SessionPlan shortPlan() {
    final template = SessionTemplates.shortSharp;
    var settings = SessionSettings.fromTemplate(template);
    for (final phase in settings.phases) {
      settings = settings.withPhase(
        phase.phase.isRoundBased
            ? phase.copyWith(rounds: 3, workSeconds: 60, restSeconds: 30)
            : phase.copyWith(totalSeconds: 300),
      );
    }
    return SessionPlanBuilder.build(template, settings);
  }

  setUp(() {
    voice = SilentCoachVoice();
    plan = shortPlan();
    engine = SessionEngine(
      plan: plan,
      voice: voice,
      // Long enough that the real timer never fires; tests drive `advance`.
      tickInterval: const Duration(hours: 1),
    );
    addTearDown(engine.dispose);
  });

  test('starts on the first segment and fires its opening cue', () {
    expect(engine.status, SessionStatus.ready);
    engine.start();
    expect(engine.status, SessionStatus.running);
    expect(engine.currentSegment, plan.segments.first);
    expect(engine.currentSegment!.phase, SessionPhase.warmUp);
    expect(voice.spoken, isNotEmpty);
  });

  test('the clock counts down within a segment', () {
    engine.start();
    final duration = engine.currentSegment!.duration;
    engine.advance(const Duration(seconds: 10));
    expect(engine.elapsedInSegment, const Duration(seconds: 10));
    expect(engine.remainingInSegment, duration - const Duration(seconds: 10));
    expect(engine.segmentIndex, 0);
  });

  test('crossing a boundary moves to the next segment and keeps the '
      'overshoot', () {
    engine.start();
    final first = engine.currentSegment!;
    engine.advance(first.duration + const Duration(seconds: 4));
    expect(engine.segmentIndex, 1);
    expect(engine.elapsedInSegment, const Duration(seconds: 4));
  });

  test('a single large advance walks several segments without losing cues', () {
    engine.start();
    engine.advance(const Duration(minutes: 6));
    expect(engine.segmentIndex, greaterThan(1));
    // Every segment it passed through announced itself.
    final announced = voice.spoken.length;
    expect(announced, greaterThanOrEqualTo(engine.segmentIndex + 1));
  });

  test('pause stops the clock and silences the coach', () {
    engine.start();
    engine.advance(const Duration(seconds: 5));
    engine.pause();
    expect(engine.status, SessionStatus.paused);
    expect(voice.silenceCount, 1);

    engine.advance(const Duration(seconds: 30));
    expect(engine.elapsedInSegment, const Duration(seconds: 5));

    engine.start();
    engine.advance(const Duration(seconds: 5));
    expect(engine.elapsedInSegment, const Duration(seconds: 10));
  });

  test('skip jumps to the next segment and announces it', () {
    engine.start();
    final before = voice.spoken.length;
    engine.skipSegment();
    expect(engine.segmentIndex, 1);
    expect(engine.elapsedInSegment, Duration.zero);
    expect(voice.spoken.length, greaterThan(before));
  });

  test('back restarts the segment, then steps back', () {
    engine.start();
    engine.skipSegment();
    engine.advance(const Duration(seconds: 20));

    engine.previousSegment();
    expect(engine.segmentIndex, 1, reason: 'restarts the current segment');
    expect(engine.elapsedInSegment, Duration.zero);

    engine.previousSegment();
    expect(engine.segmentIndex, 0, reason: 'now steps back');
  });

  test('the bell rings at the top of every round', () {
    engine.start();
    engine.advance(plan.totalDuration);
    final bells = voice.sounds.where((s) => s == CueSound.bell).length;
    expect(bells, plan.roundCount);
  });

  test('running to the end completes the session and plays the recap', () {
    engine.start();
    engine.advance(plan.totalDuration + const Duration(seconds: 1));
    expect(engine.status, SessionStatus.completed);
    expect(engine.sessionRemaining, Duration.zero);
    expect(voice.sounds, contains(CueSound.finish));
    expect(voice.spoken.last, contains('rounds'));
  });

  test('muting the coach keeps the bells', () {
    engine
      ..setVoiceEnabled(false)
      ..start()
      ..advance(const Duration(minutes: 6));
    expect(voice.spoken, isEmpty);
    expect(voice.sounds, isNotEmpty);
  });

  test('muting the sounds keeps the coach', () {
    engine
      ..setSoundEnabled(false)
      ..start()
      ..advance(const Duration(minutes: 6));
    expect(voice.sounds, isEmpty);
    expect(voice.spoken, isNotEmpty);
  });

  test('abandoning a session stops it without a recap', () {
    engine.start();
    engine.advance(const Duration(seconds: 30));
    engine.abandon();
    expect(engine.status, SessionStatus.completed);
    expect(voice.sounds, isNot(contains(CueSound.finish)));
  });

  test('session progress tracks the plan', () {
    engine.start();
    expect(engine.sessionProgress, 0);
    engine.advance(plan.totalDuration ~/ 2);
    expect(engine.sessionProgress, closeTo(0.5, 0.01));
  });

  test('the next work segment skips over rest', () {
    engine.start();
    // Walk to the first rest of the conditioning phase.
    while (!(engine.currentSegment?.isRest ?? false)) {
      engine.skipSegment();
    }
    expect(engine.nextWorkSegment!.isWork, isTrue);
  });
}
