/// Short sounds the coach uses alongside speech.
enum CueSound {
  /// Round start.
  bell('bell.wav'),

  /// Round end.
  endBell('end_bell.wav'),

  /// Last ten seconds of work.
  tick('tick.wav'),

  /// Rest is nearly over.
  warning('warning.wav'),

  /// Session complete.
  finish('finish.wav');

  const CueSound(this.asset);

  /// Path relative to the bundled asset root.
  final String asset;

  String get assetPath => 'audio/$asset';
}

/// How important a cue is when several land close together.
///
/// The spec's rule is that the coach does not talk over you; the corollary is
/// that when a technique reminder collides with a round-end call, the round-end
/// call wins and the reminder is dropped rather than queued behind it.
enum CuePriority {
  /// Round starts and ends. Never dropped.
  critical,

  /// Halfway, ten seconds, next-round previews.
  important,

  /// Technique reminders.
  routine,
}

/// A cue with a fixed offset inside its segment.
class ScheduledCue {
  const ScheduledCue({
    required this.offset,
    required this.priority,
    this.speech,
    this.sound,
  }) : assert(
         speech != null || sound != null,
         'a cue must say or play something',
       );

  /// Time from the start of the segment.
  final Duration offset;

  final CuePriority priority;

  /// Spoken text. Also shown as the on-screen coach line.
  final String? speech;

  final CueSound? sound;

  @override
  String toString() =>
      'ScheduledCue(${offset.inSeconds}s, ${priority.name}, "$speech")';
}

/// A cue at the moment it fires, with the segment it belongs to.
class CoachCue {
  const CoachCue({required this.segmentIndex, required this.cue});

  final int segmentIndex;
  final ScheduledCue cue;

  String? get speech => cue.speech;
  CueSound? get sound => cue.sound;
  CuePriority get priority => cue.priority;
}
