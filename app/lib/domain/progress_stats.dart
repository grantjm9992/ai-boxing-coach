import 'session_record.dart';

/// One `(date, value)` sample in a trend series.
class ProgressPoint {
  const ProgressPoint({required this.date, required this.value});
  final DateTime date;
  final double value;
}

/// A named technique flag and how often it came up across analysed rounds.
class ErrorTally {
  const ErrorTally({required this.label, required this.count});
  final String label;
  final int count;
}

/// An ordered trend line plus the convenience readings the UI wants: the latest
/// value, the baseline (first), and the change between them.
class TrendSeries {
  const TrendSeries(this.points);

  final List<ProgressPoint> points;

  bool get isEmpty => points.isEmpty;

  /// Two points is the minimum to speak of a trend at all.
  bool get hasTrend => points.length >= 2;

  double? get latest => points.isEmpty ? null : points.last.value;
  double? get first => points.isEmpty ? null : points.first.value;

  /// Latest minus baseline — positive is "up". Null until there's a trend.
  double? get delta => hasTrend ? points.last.value - points.first.value : null;

  /// Largest value in the series, for scaling a chart. 0 when empty.
  double get max =>
      points.isEmpty ? 0 : points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
}

/// The whole Progress view, computed from the session history. Everything here
/// comes from real per-round analysis (guard return rate, punches thrown, the
/// flagged top correction) — no invented metrics — so a session that wasn't
/// analysed simply contributes nothing to a series.
///
/// Pure and injectable: [ProgressStats.from] is unit-tested directly, with no
/// store, screen or clock.
class ProgressStats {
  const ProgressStats({
    required this.sessionCount,
    required this.analysedRoundCount,
    required this.totalWorkSeconds,
    required this.totalPunches,
    required this.guardReturn,
    required this.punchVolume,
    required this.recurringErrors,
    required this.categorySeconds,
  });

  /// Total completed sessions in history.
  final int sessionCount;

  /// Rounds that carry an analysis summary (the ones a camera actually saw).
  final int analysedRoundCount;

  final int totalWorkSeconds;
  final int totalPunches;

  /// Per-session average guard-return rate (0..1), oldest → newest.
  final TrendSeries guardReturn;

  /// Per-session total punches thrown, oldest → newest.
  final TrendSeries punchVolume;

  /// The most frequently flagged corrections, most common first.
  final List<ErrorTally> recurringErrors;

  /// All-time weighted working seconds per category key.
  final Map<String, int> categorySeconds;

  bool get isEmpty => sessionCount == 0;

  /// True once there's enough analysed history for the trends to mean anything.
  bool get hasAnalysis => analysedRoundCount > 0;

  /// Build the stats from session history. Sessions are ordered oldest → newest
  /// so every series reads left-to-right as time.
  factory ProgressStats.from(
    Iterable<SessionRecord> sessions, {
    int maxRecurring = 6,
  }) {
    final ordered = sessions.toList()
      ..sort((a, b) => a.completedAt.compareTo(b.completedAt));

    var analysedRounds = 0;
    var totalWork = 0;
    var totalPunches = 0;
    final guardPoints = <ProgressPoint>[];
    final punchPoints = <ProgressPoint>[];
    final errorCounts = <String, int>{};
    final categoryTotals = <String, int>{};

    for (final session in ordered) {
      totalWork += session.workSeconds;
      session.categorySeconds.forEach((key, seconds) {
        categoryTotals[key] = (categoryTotals[key] ?? 0) + seconds;
      });

      final guardRates = <double>[];
      var sessionPunches = 0;
      var sessionHadPunchData = false;

      for (final round in session.rounds) {
        if (round.summary != null) analysedRounds++;

        final guard = round.guardReturnRate;
        if (guard != null) guardRates.add(guard);

        final punches = round.punchesThrown;
        if (punches != null) {
          sessionPunches += punches;
          sessionHadPunchData = true;
        }

        final correction = round.topCorrection;
        if (correction != null && correction.trim().isNotEmpty) {
          final label = correction.trim();
          errorCounts[label] = (errorCounts[label] ?? 0) + 1;
        }
      }

      if (guardRates.isNotEmpty) {
        final avg = guardRates.reduce((a, b) => a + b) / guardRates.length;
        guardPoints.add(ProgressPoint(date: session.completedAt, value: avg));
      }
      if (sessionHadPunchData) {
        totalPunches += sessionPunches;
        punchPoints.add(
          ProgressPoint(date: session.completedAt, value: sessionPunches.toDouble()),
        );
      }
    }

    final recurring = errorCounts.entries
        .map((e) => ErrorTally(label: e.key, count: e.value))
        .toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.label.compareTo(b.label);
      });

    return ProgressStats(
      sessionCount: ordered.length,
      analysedRoundCount: analysedRounds,
      totalWorkSeconds: totalWork,
      totalPunches: totalPunches,
      guardReturn: TrendSeries(guardPoints),
      punchVolume: TrendSeries(punchPoints),
      recurringErrors: recurring.take(maxRecurring).toList(),
      categorySeconds: categoryTotals,
    );
  }
}
