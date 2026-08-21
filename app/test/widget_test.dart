import 'package:boxing_coach/data/session_templates.dart';
import 'package:boxing_coach/domain/session_settings.dart';
import 'package:boxing_coach/engine/session_plan_builder.dart';
import 'package:boxing_coach/services/coach_voice.dart';
import 'package:boxing_coach/ui/screens/exercise_library_screen.dart';
import 'package:boxing_coach/ui/screens/home_screen.dart';
import 'package:boxing_coach/ui/screens/session_screen.dart';
import 'package:boxing_coach/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the home screen lists every template', (tester) async {
    // HomeScreen directly: BoxingCoachApp is now behind an auth gate, which
    // needs an initialised Supabase this unit test has no business booting.
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const HomeScreen()),
    );
    await tester.pumpAndSettle();

    for (final template in SessionTemplates.all) {
      // The picker scrolls; the test viewport is shorter than a phone.
      await tester.scrollUntilVisible(
        find.text(template.name),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text(template.name),
        findsOneWidget,
        reason: '${template.id} is missing from the picker',
      );
    }
  });

  testWidgets('the exercise library filters by phase', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const ExerciseLibraryScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Joint circles'), findsOneWidget);

    // The phase filters scroll horizontally.
    await tester.dragUntilVisible(
      find.text('Technical work'),
      find.byType(SingleChildScrollView).first,
      const Offset(-120, 0),
    );
    await tester.tap(find.text('Technical work'));
    await tester.pumpAndSettle();

    expect(find.text('Joint circles'), findsNothing);
    expect(find.text('Jab mechanics'), findsOneWidget);
  });

  testWidgets('the session screen shows the clock and the current round', (
    tester,
  ) async {
    const template = SessionTemplates.shortSharp;
    final plan = SessionPlanBuilder.build(
      template,
      SessionSettings.fromTemplate(template),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: SessionScreen(plan: plan, voice: SilentCoachVoice()),
      ),
    );
    await tester.pump();

    expect(find.text('WARM-UP'), findsOneWidget);
    expect(find.text(plan.segments.first.title), findsOneWidget);
    // The coach line shows what was just said.
    expect(find.text('COACH'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);

    // Skipping ahead advances the displayed segment.
    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pump();
    expect(find.text(plan.segments[1].title), findsOneWidget);
  });
}
