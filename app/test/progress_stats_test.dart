import 'package:boxing_coach/domain/progress_stats.dart';
import 'package:boxing_coach/domain/session_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RoundSummary round({
    int index = 0,
    String? summary = 'ok',
    String? topCorrection,
    int? punchesThrown,
    double? guardReturnRate,
  }) =>
      RoundSummary(
        segmentIndex: index,
        title: 'Round',
        summary: summary,
        topCorrection: topCorrection,
        punchesThrown: punchesThrown,
        guardReturnRate: guardReturnRate,
      );

  SessionRecord session(
    String id,
    DateTime when, {
    int workSeconds = 300,
    List<RoundSummary> rounds = const <RoundSummary>[],
    Map<String, int> categorySeconds = const <String, int>{},
  }) =>
      SessionRecord(
        sessionId: id,
        templateName: 'Test',
        completedAt: when,
        totalSeconds: 600,
        workSeconds: workSeconds,
        roundCount: rounds.length,
        categorySeconds: categorySeconds,
        rounds: rounds,
      );

  final day1 = DateTime(2026, 8, 3);
  final day2 = DateTime(2026, 8, 4);

  test('empty history yields an empty, analysis-free stats object', () {
    final stats = ProgressStats.from(const <SessionRecord>[]);
    expect(stats.isEmpty, isTrue);
    expect(stats.hasAnalysis, isFalse);
    expect(stats.guardReturn.isEmpty, isTrue);
    expect(stats.recurringErrors, isEmpty);
  });

  test('orders series oldest → newest regardless of input order', () {
    final stats = ProgressStats.from(<SessionRecord>[
      session('b', day2, rounds: [round(guardReturnRate: 0.9)]),
      session('a', day1, rounds: [round(guardReturnRate: 0.6)]),
    ]);
    final pts = stats.guardReturn.points;
    expect(pts.map((p) => p.value), <double>[0.6, 0.9]);
    expect(stats.guardReturn.first, 0.6);
    expect(stats.guardReturn.latest, 0.9);
    expect(stats.guardReturn.delta, closeTo(0.3, 1e-9));
  });

  test('guard series is the per-session average of its rounds', () {
    final stats = ProgressStats.from(<SessionRecord>[
      session('s', day1, rounds: [
        round(guardReturnRate: 0.8),
        round(index: 1, guardReturnRate: 0.6),
        round(index: 2), // no guard data — ignored in the average
      ]),
    ]);
    expect(stats.guardReturn.points.single.value, closeTo(0.7, 1e-9));
  });

  test('counts analysed rounds and totals punches + work time', () {
    final stats = ProgressStats.from(<SessionRecord>[
      session('s1', day1, rounds: [
        round(punchesThrown: 40),
        round(index: 1, summary: null), // not analysed, no punch data
      ]),
      session('s2', day2, workSeconds: 200, rounds: [
        round(punchesThrown: 55),
      ]),
    ]);
    expect(stats.sessionCount, 2);
    expect(stats.analysedRoundCount, 2); // the two with a summary
    expect(stats.totalPunches, 95);
    expect(stats.totalWorkSeconds, 500); // 300 default + 200
    expect(stats.punchVolume.points.map((p) => p.value), <double>[40, 55]);
  });

  test('recurring errors tally across sessions, most common first', () {
    final stats = ProgressStats.from(<SessionRecord>[
      session('s1', day1, rounds: [
        round(topCorrection: 'Lead hand drops'),
        round(index: 1, topCorrection: 'Rotate the hips'),
      ]),
      session('s2', day2, rounds: [
        round(topCorrection: 'Lead hand drops'),
        round(index: 1, topCorrection: '  '), // blank — ignored
      ]),
    ]);
    expect(stats.recurringErrors.first.label, 'Lead hand drops');
    expect(stats.recurringErrors.first.count, 2);
    expect(stats.recurringErrors.map((e) => e.label),
        <String>['Lead hand drops', 'Rotate the hips']);
  });

  test('aggregates category seconds across sessions', () {
    final stats = ProgressStats.from(<SessionRecord>[
      session('s1', day1, categorySeconds: {'defence': 60, 'power': 30}),
      session('s2', day2, categorySeconds: {'defence': 40}),
    ]);
    expect(stats.categorySeconds['defence'], 100);
    expect(stats.categorySeconds['power'], 30);
  });

  test('a single point is not yet a trend', () {
    final stats = ProgressStats.from(<SessionRecord>[
      session('s', day1, rounds: [round(guardReturnRate: 0.75)]),
    ]);
    expect(stats.guardReturn.hasTrend, isFalse);
    expect(stats.guardReturn.delta, isNull);
    expect(stats.guardReturn.latest, 0.75);
  });
}
