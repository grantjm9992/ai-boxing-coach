/// Whether a video picked from the gallery can be imported as a shadow round,
/// and what to tell the user when it can't.
///
/// Pure — no plugins, no I/O — so the bounds are unit-testable. The caller
/// probes the file for its duration and hands the result here.
library;

/// Below this there isn't enough movement to read: the rules need a handful of
/// punches and guard returns before they say anything useful.
const Duration kMinImportedRound = Duration(seconds: 10);

/// Above this the import gets expensive in both directions — pose estimation
/// samples ~30 frames a second on-device, and Full AI review uploads the whole
/// file. Recorded rounds top out at 3 minutes ([DurationSelector.max]); 5 leaves
/// room for a clip that wasn't filmed to a boxing timer.
const Duration kMaxImportedRound = Duration(minutes: 5);

/// The verdict on a picked file.
sealed class ImportCheck {
  const ImportCheck();

  /// The file is usable; [duration] is its measured length.
  const factory ImportCheck.ok(Duration duration) = ImportOk;

  /// The file can't be imported; [message] is shown to the user as-is.
  const factory ImportCheck.rejected(String message) = ImportRejected;
}

class ImportOk extends ImportCheck {
  const ImportOk(this.duration);
  final Duration duration;
}

class ImportRejected extends ImportCheck {
  const ImportRejected(this.message);
  final String message;
}

/// Checks a picked video's [duration] against the import bounds. A null
/// duration means the probe couldn't read the file — if the player can't decode
/// it, neither can the pose estimator, so it's rejected rather than imported
/// into a round that would fail to analyse.
ImportCheck checkImportedVideo(Duration? duration) {
  if (duration == null || duration <= Duration.zero) {
    return const ImportCheck.rejected(
      "That video couldn't be read. Try a different file, or one recorded on "
      'this phone.',
    );
  }
  if (duration < kMinImportedRound) {
    return ImportCheck.rejected(
      'That clip is only ${_secondsLabel(duration)} long. Import at least '
      '${_secondsLabel(kMinImportedRound)} of work so there is something to '
      'read.',
    );
  }
  if (duration > kMaxImportedRound) {
    return ImportCheck.rejected(
      'That video is ${_minutesLabel(duration)} long — the limit is '
      '${_minutesLabel(kMaxImportedRound)}. Trim it to a round and try again.',
    );
  }
  return ImportCheck.ok(duration);
}

String _secondsLabel(Duration d) {
  final seconds = d.inSeconds;
  return '$seconds second${seconds == 1 ? '' : 's'}';
}

String _minutesLabel(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 1) return _secondsLabel(d);
  final seconds = d.inSeconds % 60;
  if (seconds == 0) return '$minutes minute${minutes == 1 ? '' : 's'}';
  return '$minutes min ${seconds}s';
}
