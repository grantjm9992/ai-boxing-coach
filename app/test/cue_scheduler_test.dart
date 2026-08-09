import 'package:boxing_coach/data/session_templates.dart';
import 'package:boxing_coach/domain/session_phase.dart';
import 'package:boxing_coach/domain/session_plan.dart';
import 'package:boxing_coach/domain/session_settings.dart';
import 'package:boxing_coach/engine/coach_cue.dart';
import 'package:boxing_coach/engine/cue_scheduler.dart';
import 'package:boxing_coach/engine/session_plan_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const template = SessionTemplates.balancedFull;
  final plan = SessionPlanBuilder.build(
    template,
    SessionSettings.fromTemplate(template),
  );
  final script = CueScheduler.schedule(plan);

  List<ScheduledCue> cuesFor(SessionSegment segment) => script[segment.index]!;

  SessionSegment firstShadowRound() => plan
      .segmentsFor(SessionPhase.shadow)
      .firstWhere((segment) => segment.isWork);

  SessionSegment firstShadowRest() => plan
      .segmentsFor(SessionPhase.shadow)
      .firstWhere((segment) => segment.isRest);

  group('round calls', () {
    test('a round opens with a bell and announces itself', () {
      final cues = cuesFor(firstShadowRound());
      expect(cues.first.offset, Duration.zero);
      expect(cues.first.sound, CueSound.bell);
      expect(cues.first.priority, CuePriority.critical);
      expect(cues.first.speech, contains('Round 1 of'));
      expect(cues.first.speech, endsWith('Go.'));
    });

    test('the first round of a phase introduces the phase', () {
      final cues = cuesFor(firstShadowRound());
      expect(cues.first.speech, contains(SessionPhase.shadow.coachIntro));
    });

    test('a mid-phase round does not repeat the phase introduction', () {
      final second = plan
          .segmentsFor(SessionPhase.shadow)
          .where((segment) => segment.isWork)
          .elementAt(1);
      expect(
        cuesFor(second).first.speech,
        isNot(contains(SessionPhase.shadow.coachIntro)),
      );
    });

    test('the last round of a phase is called out', () {
      final last = plan
          .segmentsFor(SessionPhase.shadow)
          .where((segment) => segment.isWork)
          .last;
      expect(cuesFor(last).first.speech, contains('Last round'));
    });

    test('halfway and ten-second calls land where they should', () {
      final round = firstShadowRound();
      final cues = cuesFor(round);
      final halfway = cues.firstWhere(
        (cue) => cue.speech?.startsWith('Halfway') ?? false,
      );
      expect(halfway.offset.inSeconds, round.duration.inSeconds ~/ 2);

      final ten = cues.firstWhere((cue) => cue.sound == CueSound.tick);
      expect(ten.offset, round.duration - const Duration(seconds: 10));
      expect(ten.speech, contains('Ten seconds'));
    });

    test('technique reminders are spaced and stop before the finish', () {
      final round = firstShadowRound();
      final reminders = cuesFor(
        round,
      ).where((cue) => cue.priority == CuePriority.routine).toList();
      expect(reminders, isNotEmpty);

      for (final reminder in reminders) {
        expect(reminder.speech, isNotNull);
        expect(
          round.duration - reminder.offset,
          greaterThan(const Duration(seconds: 14)),
          reason: 'a reminder crowded the ten-second call',
        );
      }
      for (var i = 1; i < reminders.length; i++) {
        expect(
          reminders[i].offset - reminders[i - 1].offset,
          greaterThanOrEqualTo(const Duration(seconds: 20)),
        );
      }
    });

    test('reminders come from the exercise being worked', () {
      final round = firstShadowRound();
      final reminders = cuesFor(round)
          .where((cue) => cue.priority == CuePriority.routine)
          .map((cue) => cue.speech)
          .toList();
      for (final reminder in reminders) {
        expect(round.exercise.cues, contains(reminder));
      }
    });

    test('no two cues in a segment collide', () {
      for (final cues in script.values) {
        for (var i = 1; i < cues.length; i++) {
          expect(
            cues[i].offset - cues[i - 1].offset,
            greaterThanOrEqualTo(const Duration(seconds: 4)),
          );
        }
      }
    });
  });

  group('rest calls', () {
    test('rest opens with the end bell', () {
      final cues = cuesFor(firstShadowRest());
      expect(cues.first.sound, CueSound.endBell);
      expect(cues.first.speech, startsWith('Rest'));
    });

    test('the coach previews the next round before it starts', () {
      final rest = firstShadowRest();
      final preview = cuesFor(
        rest,
      ).firstWhere((cue) => cue.speech?.startsWith('Get ready') ?? false);
      expect(preview.offset, rest.duration - const Duration(seconds: 30));

      final next = plan.segmentAt(rest.index + 1)!;
      expect(preview.speech, contains(next.title.toLowerCase()));
    });

    test('the preview names the phase when one is about to change', () {
      final lastConditioningRest = plan
          .segmentsFor(SessionPhase.conditioning)
          .lastWhere((segment) => segment.isRest);
      final preview = cuesFor(
        lastConditioningRest,
      ).firstWhere((cue) => cue.speech?.startsWith('Get ready') ?? false);
      expect(preview.speech, contains(SessionPhase.shadow.label));
    });

    test('the end of a phase is acknowledged', () {
      final lastRest = plan
          .segmentsFor(SessionPhase.conditioning)
          .lastWhere((segment) => segment.isRest);
      expect(cuesFor(lastRest).first.speech, contains('done'));
    });
  });

  group('session-level cues', () {
    test('the halfway point of the session is mentioned exactly once', () {
      final mentions = script.values
          .expand((cues) => cues)
          .where(
            (cue) =>
                cue.speech?.contains('halfway through the session') ?? false,
          )
          .length;
      expect(mentions, 1);
    });

    test('completion summarises the session', () {
      final cues = CueScheduler.completionCues(plan);
      expect(cues.first.sound, CueSound.finish);
      expect(cues.first.speech, contains('complete'));
      expect(cues.last.speech, contains('${plan.roundCount} rounds'));
    });

    test('the script is deterministic', () {
      final again = CueScheduler.schedule(
        SessionPlanBuilder.build(
          template,
          SessionSettings.fromTemplate(template),
        ),
      );
      for (final entry in script.entries) {
        expect(
          again[entry.key]!.map((cue) => cue.speech).toList(),
          entry.value.map((cue) => cue.speech).toList(),
        );
      }
    });

    test('every segment gets at least an opening cue', () {
      for (final segment in plan.segments) {
        expect(script[segment.index], isNotEmpty);
        expect(script[segment.index]!.first.offset, Duration.zero);
      }
    });
  });
}
