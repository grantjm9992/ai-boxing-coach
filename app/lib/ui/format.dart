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

  /// `48 min`, rounded to the nearest minute.
  static String minutes(Duration duration) {
    final value = (duration.inSeconds / 60).round();
    return '$value min';
  }

  /// `2 × 3:00` style round description.
  static String rounds(int count, int workSeconds, int restSeconds) {
    final work = clock(Duration(seconds: workSeconds));
    final rest = clock(Duration(seconds: restSeconds));
    return '$count × $work work / $rest rest';
  }
}
