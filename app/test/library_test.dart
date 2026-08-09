import 'package:boxing_coach/data/exercise_library.dart';
import 'package:boxing_coach/data/session_templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('exercise library', () {
    test('keys are unique', () {
      final keys = ExerciseLibrary.all.map((e) => e.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('every exercise is tagged with at least one category', () {
      for (final exercise in ExerciseLibrary.all) {
        expect(
          exercise.categoryWeights,
          isNotEmpty,
          reason: '${exercise.key} has no category tags',
        );
      }
    });

    test('category weights sum to roughly one', () {
      // The balance view treats a segment's duration as the training load it
      // shares out, so the weights have to behave like proportions.
      for (final exercise in ExerciseLibrary.all) {
        final sum = exercise.categoryWeights.values.fold<double>(
          0,
          (total, weight) => total + weight,
        );
        expect(
          sum,
          closeTo(1, 0.001),
          reason: '${exercise.key} weights sum to $sum',
        );
      }
    });

    test('weights are proportions, not arbitrary numbers', () {
      for (final exercise in ExerciseLibrary.all) {
        for (final weight in exercise.categoryWeights.values) {
          expect(weight, greaterThan(0));
          expect(weight, lessThanOrEqualTo(1));
        }
      }
    });

    test('every phase has exercises', () {
      for (final phase in ExerciseLibrary.all.map((e) => e.phase).toSet()) {
        expect(ExerciseLibrary.forPhase(phase), isNotEmpty);
      }
    });

    test('technical drills carry a setup cue', () {
      // The coach describes the drill before it starts; a technical round with
      // nothing to say about the setup is an unfinished drill.
      for (final exercise in ExerciseLibrary.all) {
        if (exercise.phase.key != 'technical') continue;
        expect(
          exercise.setupCue,
          isNotNull,
          reason: '${exercise.key} has no setup cue',
        );
      }
    });
  });

  group('session templates', () {
    test('every item references a real exercise in the right phase', () {
      for (final template in SessionTemplates.all) {
        for (final templatePhase in template.phases) {
          for (final item in templatePhase.items) {
            expect(
              ExerciseLibrary.contains(item.exerciseKey),
              isTrue,
              reason: '${template.id} references ${item.exerciseKey}',
            );
            expect(
              ExerciseLibrary.byKey(item.exerciseKey).phase,
              templatePhase.phase,
              reason:
                  '${item.exerciseKey} is not a '
                  '${templatePhase.phase.key} exercise',
            );
          }
        }
      }
    });

    test('every template runs the full five-phase arc in order', () {
      for (final template in SessionTemplates.all) {
        expect(template.phases.map((p) => p.phase.key).toList(), <String>[
          'warmup',
          'conditioning',
          'shadow',
          'technical',
          'cooldown',
        ], reason: template.id);
      }
    });

    test('template defaults sit inside the phase bounds', () {
      for (final template in SessionTemplates.all) {
        for (final templatePhase in template.phases) {
          final bounds = templatePhase.phase.bounds;
          if (templatePhase.phase.isRoundBased) {
            expect(
              templatePhase.defaultRounds,
              inInclusiveRange(bounds.minRounds, bounds.maxRounds),
              reason: '${template.id}/${templatePhase.phase.key} rounds',
            );
            expect(
              templatePhase.defaultWorkSeconds,
              inInclusiveRange(bounds.minWorkSeconds, bounds.maxWorkSeconds),
              reason: '${template.id}/${templatePhase.phase.key} work',
            );
            expect(
              templatePhase.defaultRestSeconds,
              inInclusiveRange(bounds.minRestSeconds, bounds.maxRestSeconds),
              reason: '${template.id}/${templatePhase.phase.key} rest',
            );
          } else {
            expect(
              templatePhase.defaultTotalSeconds,
              inInclusiveRange(bounds.minTotalSeconds, bounds.maxTotalSeconds),
              reason: '${template.id}/${templatePhase.phase.key} total',
            );
          }
        }
      }
    });

    test('ids are unique', () {
      final ids = SessionTemplates.all.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });
}
