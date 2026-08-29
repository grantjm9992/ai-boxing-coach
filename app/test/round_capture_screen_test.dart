import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/analysis/session_type.dart';
import 'package:boxing_coach/services/analytics.dart';
import 'package:boxing_coach/services/round_recorder.dart';
import 'package:boxing_coach/ui/screens/round_capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared capture loop: record → analyse → pop a RoundCaptureResult. Driven
/// with a fake recorder + stubbed analysis, framing check skipped (no camera).
void main() {
  testWidgets('records, analyses and pops the result', (tester) async {
    final analytics = FakeAnalytics();
    RoundCaptureResult? popped;

    Future<RoundCaptureResult> analyse(String path, DrillContext drill) async {
      expect(drill.sessionType, SessionType.shadowBoxing);
      return RoundCaptureResult(
        analysis: RoundAnalysis(
          overallSummary: 'good round',
          sessionType: SessionType.shadowBoxing,
        ),
        durationMs: 60000,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<RoundCaptureResult>(
                MaterialPageRoute<RoundCaptureResult>(
                  builder: (_) => RoundCaptureScreen(
                    title: 'Shadow boxing',
                    sessionType: SessionType.shadowBoxing,
                    recorder: FakeRoundRecorder(),
                    analyseOverride: analyse,
                    profileLoader: () async =>
                        const DrillContext(sessionType: SessionType.shadowBoxing),
                    analytics: analytics,
                    skipFramingCheck: true,
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
    await tester.tap(find.text('Stop & analyse'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.analysis?.overallSummary, 'good round');
    expect(popped!.durationMs, 60000);
    expect(analytics.count(AnalyticsEvent.shadowBoxingStarted), 1);
  });
}
