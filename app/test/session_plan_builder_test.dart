import 'package:boxing_coach/data/session_templates.dart';
import 'package:boxing_coach/domain/session_phase.dart';
import 'package:boxing_coach/domain/session_plan.dart';
import 'package:boxing_coach/domain/session_settings.dart';
import 'package:boxing_coach/engine/session_plan_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final template = SessionTemplates.balancedFull;

  group('plan building', () {
    test('produces the phases in arc order', () {
      final plan = SessionPlanBuilder.build(
        template,
        SessionSettings.fromTemplate(template),
      );
      expect(plan.activePhases, <SessionPhase>[
        SessionPhase.warmUp,
        SessionPhase.conditioning,
        SessionPhase.shadow,
        SessionPhase.technical,
        SessionPhase.coolDown,
      ]);
    });

    test('total duration matches the configuration exactly', () {
      final settings = SessionSettings.fromTemplate(template);
      final plan = SessionPlanBuilder.build(template, settings);
      expect(plan.totalDuration, settings.totalDuration);
    });

    test('segment offsets are contiguous', () {
      final plan = SessionPlanBuilder.build(
        template,
        SessionSettings.fromTemplate(template),
      );
      var expected = Duration.zero;
      for (final segment in plan.segments) {
        expect(segment.startOffset, expected);
        expected += segment.duration;
      }
      expect(expected, plan.totalDuration);
    });

    test('a continuous phase shares its total across its items', () {
      final settings = SessionSettings.fromTemplate(template);
      final warmUp = settings.forPhase(SessionPhase.warmUp)!;
      final plan = SessionPlanBuilder.build(
        template,
        settings.withPhase(warmUp.copyWith(totalSeconds: 600)),
      );
      final segments = plan.segmentsFor(SessionPhase.warmUp);
      expect(
        segments.length,
        template.phaseFor(SessionPhase.warmUp)!.items.length,
      );
      expect(
        plan.durationOf(SessionPhase.warmUp),
        const Duration(seconds: 600),
      );
      for (final segment in segments) {
        expect(
          segment.duration.inSeconds,
          greaterThanOrEqualTo(SessionPlanBuilder.minimumSegmentSeconds),
        );
      }
    });

    test('a short continuous phase drops trailing items rather than '
        'producing unusable slivers', () {
      final settings = SessionSettings.fromTemplate(
        SessionTemplates.shortSharp,
      );
      final coolDown = settings.forPhase(SessionPhase.coolDown)!;
      // Well below the bounds; clamping brings it back to the five-minute floor.
      final plan = SessionPlanBuilder.build(
        SessionTemplates.shortSharp,
        settings.withPhase(coolDown.copyWith(totalSeconds: 60)),
      );
      for (final segment in plan.segmentsFor(SessionPhase.coolDown)) {
        expect(
          segment.duration.inSeconds,
          greaterThanOrEqualTo(SessionPlanBuilder.minimumSegmentSeconds),
        );
      }
    });

    test('round phases alternate work and rest', () {
      final plan = SessionPlanBuilder.build(
        template,
        SessionSettings.fromTemplate(template),
      );
      final shadow = plan.segmentsFor(SessionPhase.shadow);
      for (var i = 0; i < shadow.length; i++) {
        expect(shadow[i].kind, i.isEven ? SegmentKind.work : SegmentKind.rest);
      }
      expect(shadow.last.isLastOfPhase, isTrue);
      expect(shadow.first.isFirstOfPhase, isTrue);
    });

    test('rounds cycle through the template items when the user adds more', () {
      final settings = SessionSettings.fromTemplate(template);
      final shadow = settings.forPhase(SessionPhase.shadow)!;
      final plan = SessionPlanBuilder.build(
        template,
        settings.withPhase(shadow.copyWith(rounds: 8)),
      );
      final work = plan
          .segmentsFor(SessionPhase.shadow)
          .where((segment) => segment.isWork)
          .toList();
      expect(work.length, 8);
      // Four themes in the template, so round five repeats round one.
      expect(work[4].exercise.key, work[0].exercise.key);
      expect(work[4].roundNumber, 5);
      expect(work[4].roundsInPhase, 8);
    });

    test('a disabled optional phase disappears from the plan', () {
      final settings = SessionSettings.fromTemplate(template);
      final conditioning = settings.forPhase(SessionPhase.conditioning)!;
      final plan = SessionPlanBuilder.build(
        template,
        settings.withPhase(conditioning.copyWith(enabled: false)),
      );
      expect(plan.activePhases, isNot(contains(SessionPhase.conditioning)));
      expect(plan.activePhases, contains(SessionPhase.warmUp));
    });

    test('category breakdown counts working time only', () {
      final plan = SessionPlanBuilder.build(
        template,
        SessionSettings.fromTemplate(template),
      );
      final total = plan.categoryBreakdown.values.fold<int>(
        0,
        (sum, duration) => sum + duration.inSeconds,
      );
      // Weights sum to one per exercise, so the breakdown adds up to the
      // working time — within a second or two of rounding.
      expect(total, closeTo(plan.workDuration.inSeconds, 3));
      expect(plan.workDuration, lessThan(plan.totalDuration));
    });
  });

  group('configuration bounds', () {
    test('out-of-range values are clamped, not accepted', () {
      final settings = SessionSettings.fromTemplate(template);
      final shadow = settings.forPhase(SessionPhase.shadow)!;
      final bounds = SessionPhase.shadow.bounds;

      expect(shadow.copyWith(rounds: 99).rounds, bounds.maxRounds);
      expect(shadow.copyWith(rounds: 0).rounds, bounds.minRounds);
      expect(
        shadow.copyWith(workSeconds: 5).workSeconds,
        bounds.minWorkSeconds,
      );
      expect(
        shadow.copyWith(restSeconds: 600).restSeconds,
        bounds.maxRestSeconds,
      );
    });

    test('the warm-up cannot be disabled', () {
      final settings = SessionSettings.fromTemplate(template);
      final warmUp = settings.forPhase(SessionPhase.warmUp)!;
      expect(warmUp.copyWith(enabled: false).enabled, isTrue);
    });

    test('settings survive a round trip through storage', () {
      final settings = SessionSettings.fromTemplate(template);
      final shadow = settings.forPhase(SessionPhase.shadow)!;
      final modified = settings
          .withPhase(shadow.copyWith(rounds: 6, workSeconds: 120))
          .copyWith(voiceEnabled: false);

      final restored = SessionSettings.fromJson(modified.toJson(), template);

      expect(restored.voiceEnabled, isFalse);
      expect(restored.forPhase(SessionPhase.shadow)!.rounds, 6);
      expect(restored.forPhase(SessionPhase.shadow)!.workSeconds, 120);
      expect(restored.totalDuration, modified.totalDuration);
    });
  });
}
