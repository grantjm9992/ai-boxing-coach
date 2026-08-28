import 'package:boxing_coach/analysis/combination.dart';
import 'package:boxing_coach/analysis/combination_analysis.dart';
import 'package:boxing_coach/analysis/drill_matching.dart';
import 'package:boxing_coach/analysis/punch.dart';
import 'package:boxing_coach/data/combination_library.dart';
import 'package:boxing_coach/ui/screens/combination_detail_screen.dart';
import 'package:boxing_coach/ui/screens/combination_library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 5 smoke tests: the library and detail screens build and render their
/// content, including a drill result.
void main() {
  testWidgets('library screen lists combinations', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CombinationLibraryScreen()),
    );
    expect(find.text('Combinations'), findsOneWidget);
    expect(find.text('Jab → Cross → Lead Hook'), findsOneWidget);
  });

  testWidgets('detail screen shows sequence and coaching points',
      (tester) async {
    _useTallSurface(tester);
    final combo = CombinationLibrary.byId('combo_1_2_3')!;
    await tester.pumpWidget(
      MaterialApp(home: CombinationDetailScreen(combo: combo)),
    );
    expect(find.text(combo.name), findsOneWidget);
    expect(find.text('COACHING POINTS'), findsOneWidget);
    expect(find.text('Start drill'), findsOneWidget);
  });

  testWidgets('detail screen renders a drill result', (tester) async {
    _useTallSurface(tester);
    final combo = CombinationLibrary.byId('combo_1_2_3')!;
    final result = evaluateDrill(<int>[1, 2, 3], <CombinationAnalysis>[
      _analysis(<int>[1, 2, 3], 88),
      _analysis(<int>[1, 2], 100),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: CombinationDetailScreen(combo: combo, result: result),
      ),
    );
    expect(find.textContaining('1/2 attempts'), findsOneWidget);
    expect(find.text('Drill again'), findsOneWidget);
  });
}

/// A tall, narrow viewport so the whole detail ListView lays out its children
/// (a lazy ListView only builds what's in view).
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

CombinationAnalysis _analysis(List<int> seq, int score) => CombinationAnalysis(
  combination: Combination(
    startMs: 0,
    endMs: 500,
    sequence: seq,
    types: <PunchType>[for (final _ in seq) PunchType.straight],
    confidence: 1.0,
    punchIndices: <int>[for (var i = 0; i < seq.length; i++) i],
  ),
  score: score,
);
