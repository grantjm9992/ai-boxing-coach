import 'package:boxing_coach/analysis/combination.dart';
import 'package:boxing_coach/analysis/combination_analysis.dart';
import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/drill_matching.dart';
import 'package:boxing_coach/analysis/punch.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/data/combination_library.dart';
import 'package:boxing_coach/services/round_recorder.dart';
import 'package:boxing_coach/ui/screens/combination_drill_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The live drill loop (brief §15): record → analyse → evaluate → pop a
/// DrillResult. Driven with a fake recorder and a stubbed analysis so the loop
/// runs without a camera or MediaPipe.
void main() {
  testWidgets('records, evaluates and pops a DrillResult', (tester) async {
    final combo = CombinationLibrary.byId('combo_1_2_3')!;
    DrillResult? popped;

    // The stubbed analysis returns two attempts: one matching 1-2-3, one not.
    Future<RoundAnalysis?> analyse(String path, DrillContext drill) async {
      expect(path, '/tmp/fake.mp4');
      return RoundAnalysis(
        overallSummary: 'x',
        combinationAnalyses: <CombinationAnalysis>[
          _analysis(<int>[1, 2, 3], 90),
          _analysis(<int>[1, 2], 100),
        ],
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<DrillResult>(
                MaterialPageRoute<DrillResult>(
                  builder: (_) => CombinationDrillScreen(
                    combo: combo,
                    recorder: FakeRoundRecorder(),
                    analyseOverride: analyse,
                    profileLoader: () async => const DrillContext(),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(); // initialise the recorder

    // Record, then stop → analyse → pop.
    await tester.tap(find.text('Start recording'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop & score'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.expected, <int>[1, 2, 3]);
    expect(popped!.totalAttempts, 2);
    expect(popped!.matchedCount, 1);
    expect(popped!.averageScore, 90);
  });

  testWidgets('no detected combinations still pops a safe empty result',
      (tester) async {
    final combo = CombinationLibrary.byId('combo_1_2')!;
    DrillResult? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<DrillResult>(
                MaterialPageRoute<DrillResult>(
                  builder: (_) => CombinationDrillScreen(
                    combo: combo,
                    recorder: FakeRoundRecorder(),
                    analyseOverride: (_, _) async => null, // no analysis
                    profileLoader: () async => const DrillContext(),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start recording'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop & score'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(popped, isNotNull);
    expect(popped!.totalAttempts, 0);
    expect(popped!.averageScore, isNull);
  });
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
