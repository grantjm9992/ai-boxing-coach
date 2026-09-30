import 'package:boxing_coach/analysis/checkpoint_evaluation.dart';
import 'package:boxing_coach/analysis/checkpoints.dart';
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

  testWidgets('detail screen lists what the coach is looking for, per punch',
      (tester) async {
    _useTallSurface(tester);
    final combo = CombinationLibrary.byId('combo_1_2_3')!;
    await tester.pumpWidget(
      MaterialApp(home: CombinationDetailScreen(combo: combo)),
    );
    expect(find.text('WHAT THE COACH IS LOOKING FOR'), findsOneWidget);
    expect(find.text('Snaps back after extension'), findsOneWidget);
    expect(find.text('Lead hand back protecting the face'), findsOneWidget);
    expect(find.text('Arm bent at about 90°'), findsOneWidget);
    // Elbows-in can only be judged from the video.
    expect(find.textContaining('Elbows in'), findsOneWidget);
    expect(find.text('AI review'), findsOneWidget);
  });

  testWidgets('drill result shows each checkpoint across the reps',
      (tester) async {
    _useTallSurface(tester);
    final combo = CombinationLibrary.byId('combo_1_2_3')!;
    final checkpoints = combo.checkpoints;
    DrillCheckpoint byId(String id) =>
        checkpoints.firstWhere((c) => c.id == id);
    final result = evaluateDrill(
      <int>[1, 2, 3],
      <CombinationAnalysis>[_analysis(<int>[1, 2, 3], 88)],
      checkpoints: <CheckpointTally>[
        CheckpointTally(checkpoint: byId('jab_snap_back'), passed: 2, failed: 1),
        CheckpointTally(checkpoint: byId('cross_elbows_in'), unmeasured: 3),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CombinationDetailScreen(combo: combo, result: result),
      ),
    );
    expect(find.text('CHECKPOINTS'), findsOneWidget);
    expect(find.text('Jab · Snaps back after extension'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
    // Graded from the video only — the list and the result both say so.
    expect(find.text('AI review'), findsNWidgets(2));
  });
}

/// A tall, narrow viewport so the whole detail ListView lays out its children
/// (a lazy ListView only builds what's in view).
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 5000);
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
