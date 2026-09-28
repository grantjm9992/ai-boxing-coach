import 'package:boxing_coach/analysis/analysis_mode.dart';
import 'package:boxing_coach/services/analysis_progress.dart';
import 'package:boxing_coach/ui/widgets/analysis_progress_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnalysisProgress', () {
    test('stages follow the mode', () {
      expect(AnalysisStage.stagesFor(AnalysisMode.offline),
          <AnalysisStage>[AnalysisStage.tracking, AnalysisStage.saving]);
      expect(AnalysisStage.stagesFor(AnalysisMode.fullFrame), <AnalysisStage>[
        AnalysisStage.tracking,
        AnalysisStage.uploading,
        AnalysisStage.reviewing,
        AnalysisStage.saving,
      ]);
    });

    test('a new fraction keeps the stage clock; a new stage restarts it', () {
      final t0 = DateTime(2026, 9, 28, 12);
      final start = AnalysisProgress.start(AnalysisMode.fullFrame, now: t0);
      final later = start.advance(AnalysisStage.tracking, 0.5,
          now: t0.add(const Duration(seconds: 30)));
      expect(later.stageStartedAt, t0);
      final uploading = later.advance(AnalysisStage.uploading, 0,
          now: t0.add(const Duration(seconds: 60)));
      expect(uploading.stageStartedAt, t0.add(const Duration(seconds: 60)));
      expect(uploading.startedAt, t0);
    });

    test('time left extrapolates the stage pace', () {
      final t0 = DateTime(2026, 9, 28, 12);
      final p = AnalysisProgress(
        mode: AnalysisMode.fullFrame,
        stage: AnalysisStage.tracking,
        fraction: 0.25,
        startedAt: t0,
        stageStartedAt: t0,
      );
      expect(p.stageRemaining(now: t0.add(const Duration(seconds: 30))),
          const Duration(seconds: 90));
      // Too early to tell, or a stage that can't measure itself.
      expect(
        AnalysisProgress(
          mode: AnalysisMode.fullFrame,
          stage: AnalysisStage.reviewing,
          startedAt: t0,
          stageStartedAt: t0,
        ).stageRemaining(now: t0),
        isNull,
      );
    });
  });

  testWidgets('the card names every stage and marks the current one',
      (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalysisProgressCard(
          progress: AnalysisProgress(
            mode: AnalysisMode.fullFrame,
            stage: AnalysisStage.uploading,
            fraction: 0.4,
            startedAt: now.subtract(const Duration(minutes: 3)),
            stageStartedAt: now.subtract(const Duration(seconds: 20)),
          ),
        ),
      ),
    ));

    expect(find.text('Analysing your round'), findsOneWidget);
    for (final stage in AnalysisStage.stagesFor(AnalysisMode.fullFrame)) {
      expect(find.text(stage.label), findsOneWidget);
    }
    expect(find.textContaining('40%'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget); // tracking done
    expect(find.textContaining('You can leave this screen'), findsOneWidget);

    // Unmount so the card's ticker and pulse are disposed.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the badge shows the stage and percentage', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalysisProgressBadge(
          progress: AnalysisProgress.start(AnalysisMode.keyframe)
              .advance(AnalysisStage.tracking, 0.62),
        ),
      ),
    ));
    expect(find.text('Tracking your movement · 62%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
