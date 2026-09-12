/// Duration formatting used across the UI and, in spoken form, nowhere — the
/// coach says "ten seconds", it never reads a clock out.
class TimeFormat {
  const TimeFormat._();

  /// `3:00`, or `1:04:30` once a session passes the hour.
  static String clock(Duration duration) {
    final total = duration.isNegative ? Duration.zero : duration;
    final hours = total.inHours;
    final minutes = total.inMinutes.remainder(60);
    final seconds = total.inSeconds.remainder(60);
    final paddedSeconds = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$paddedSeconds';
    }
    return '$minutes:$paddedSeconds';
  }

  /// `48 min`, rounded to the nearest minute. Non-zero durations that round
  /// down to zero (under 30s — e.g. one short round split across categories)
  /// show `<1 min` rather than a misleading `0 min` next to a filled bar.
  static String minutes(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds <= 0) return '0 min';
    final value = (seconds / 60).round();
    return value == 0 ? '<1 min' : '$value min';
  }

  /// `2 × 3:00` style round description.
  static String rounds(int count, int workSeconds, int restSeconds) {
    final work = clock(Duration(seconds: workSeconds));
    final rest = clock(Duration(seconds: restSeconds));
    return '$count × $work work / $rest rest';
  }
}
