import 'package:boxing_coach/ui/screens/home_screen.dart';
import 'package:boxing_coach/ui/widgets/duration_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The home page presents the three training modes as accordions.
void main() {
  testWidgets('shows the three accordions; shadow expands to a length + Start',
      (tester) async {
    tester.view.physicalSize = const Size(500, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Workouts & sessions'), findsOneWidget);
    expect(find.text('Shadow boxing'), findsOneWidget);
    expect(find.text('Combination drills'), findsOneWidget);

    // Shadow section is collapsed until tapped.
    expect(find.byType(DurationSelector), findsNothing);
    await tester.tap(find.text('Shadow boxing'));
    await tester.pumpAndSettle();
    expect(find.byType(DurationSelector), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
  });
}
