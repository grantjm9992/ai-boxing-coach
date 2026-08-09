import '../domain/exercise.dart';
import '../domain/session_phase.dart';
import '../domain/session_plan.dart';
import 'coach_cue.dart';

/// Turns a [SessionPlan] into the coach's script.
///
/// The whole script is computed up front rather than decided tick by tick.
/// That makes the coach's behaviour deterministic — the same plan always
/// produces the same cues, which is testable, and it means the engine at
/// runtime only has to compare offsets.
///
/// The rules it encodes come from the spec's "Coach behaviour" section:
/// anticipate the next round, call the round in, mark halfway and the last ten
/// seconds, drop technique reminders every twenty to thirty seconds, and
/// acknowledge milestones.
class CueScheduler {
  const CueScheduler._();

  /// First technique reminder lands here, not at the top of the round — the
  /// athlete has just been told what to do.
  static const Duration _firstReminder = Duration(seconds: 20);

  /// "Cues are spaced (every 20-30 seconds) not constant."
  static const Duration _reminderInterval = Duration(seconds: 25);

  /// No reminders in the closing stretch; the ten-second call owns it.
  static const Duration _reminderTailBuffer = Duration(seconds: 15);

  /// A reminder this close to a fixed cue is dropped rather than queued.
  static const Duration _collisionWindow = Duration(seconds: 6);

  /// Segment index → cues, sorted by offset.
  static Map<int, List<ScheduledCue>> schedule(SessionPlan plan) {
    final halfwaySegment = _sessionHalfwaySegment(plan);
    final result = <int, List<ScheduledCue>>{};

    for (final segment in plan.segments) {
      final next = plan.segmentAt(segment.index + 1);
      final cues = segment.isWork
          ? _workCues(
              segment,
              isSessionHalfway: segment.index == halfwaySegment,
            )
          : _restCues(segment, next);
      cues.sort((a, b) => a.offset.compareTo(b.offset));
      result[segment.index] = List<ScheduledCue>.unmodifiable(cues);
    }
    return result;
  }

  /// Spoken once the last segment finishes.
  static List<ScheduledCue> completionCues(SessionPlan plan) {
    final categories = plan.categoryBreakdown.entries.take(3).toList();
    final focus = categories.isEmpty
        ? ''
        : ' Most of the work went into '
              '${_joinWords(<String>[for (final entry in categories) entry.key.label.toLowerCase()])}.';

    final minutes = plan.totalDuration.inMinutes;
    final rounds = plan.roundCount;
    return <ScheduledCue>[
      const ScheduledCue(
        offset: Duration.zero,
        priority: CuePriority.critical,
        sound: CueSound.finish,
        speech: 'Session complete. Well done.',
      ),
      ScheduledCue(
        offset: const Duration(seconds: 4),
        priority: CuePriority.important,
        speech:
            '$minutes minutes, $rounds rounds.$focus '
            'Stretch, get some water, and note anything worth remembering '
            'for next time.',
      ),
    ];
  }

  // ------------------------------------------------------------------ work

  static List<ScheduledCue> _workCues(
    SessionSegment segment, {
    required bool isSessionHalfway,
  }) {
    final cues = <ScheduledCue>[
      ScheduledCue(
        offset: Duration.zero,
        priority: CuePriority.critical,
        sound: segment.roundNumber != null ? CueSound.bell : null,
        speech: _workOpening(segment, isSessionHalfway: isSessionHalfway),
      ),
    ];

    final seconds = segment.duration.inSeconds;

    if (seconds >= 100) {
      cues.add(
        ScheduledCue(
          offset: Duration(seconds: seconds ~/ 2),
          priority: CuePriority.important,
          speech: _variant(const <String>[
            'Halfway. Keep the pace.',
            'Halfway through. Same quality in the second half.',
            'Halfway. Do not let the hands drop now.',
          ], segment.index),
        ),
      );
    }

    if (seconds >= 160) {
      cues.add(
        ScheduledCue(
          offset: Duration(seconds: seconds - 30),
          priority: CuePriority.important,
          speech: 'Thirty seconds.',
        ),
      );
    }

    if (seconds >= 45) {
      cues.add(
        ScheduledCue(
          offset: Duration(seconds: seconds - 10),
          priority: CuePriority.important,
          sound: CueSound.tick,
          speech: _variant(const <String>[
            'Ten seconds. Finish strong.',
            'Ten seconds. Empty it out.',
            'Ten seconds left. Hold the form.',
          ], segment.index),
        ),
      );
    }

    cues.addAll(_reminders(segment, cues));
    return cues;
  }

  static String _workOpening(
    SessionSegment segment, {
    required bool isSessionHalfway,
  }) {
    final parts = <String>[];

    if (segment.isFirstOfPhase) {
      parts.add(segment.phase.coachIntro);
    }

    if (segment.roundNumber != null) {
      parts.add('Round ${segment.roundNumber} of ${segment.roundsInPhase}.');
      parts.add('${segment.title}.');
      if (segment.roundNumber == segment.roundsInPhase) {
        parts.add('Last round of the ${segment.phase.label.toLowerCase()}.');
      }
    } else {
      parts.add('${segment.exercise.label}.');
    }

    final note = segment.note ?? segment.exercise.setupCue;
    if (note != null && segment.phase == SessionPhase.technical) {
      parts.add(note);
    } else if (segment.roundNumber == null &&
        segment.exercise.cues.isNotEmpty) {
      parts.add(segment.exercise.cues.first);
    }

    if (isSessionHalfway) {
      parts.add('That is you halfway through the session.');
    }

    if (segment.roundNumber != null) {
      parts.add('Go.');
    }

    return parts.join(' ');
  }

  /// Technique reminders, placed on a fixed cadence and dropped wherever they
  /// would land on top of a fixed cue.
  static List<ScheduledCue> _reminders(
    SessionSegment segment,
    List<ScheduledCue> fixed,
  ) {
    final available = segment.duration - _reminderTailBuffer;
    final cues = segment.exercise.cues;
    if (cues.isEmpty || available <= _firstReminder) {
      return const <ScheduledCue>[];
    }

    final reminders = <ScheduledCue>[];
    var offset = _firstReminder;
    var cueIndex = segment.roundNumber ?? 0;

    while (offset < available) {
      final collides = fixed.any(
        (other) =>
            (other.offset - offset).abs() < _collisionWindow &&
            other.speech != null,
      );
      if (!collides) {
        reminders.add(
          ScheduledCue(
            offset: offset,
            priority: CuePriority.routine,
            speech: cues[cueIndex % cues.length],
          ),
        );
        cueIndex++;
      }
      offset += _reminderInterval;
    }
    return reminders;
  }

  // ------------------------------------------------------------------ rest

  static List<ScheduledCue> _restCues(
    SessionSegment segment,
    SessionSegment? next,
  ) {
    final seconds = segment.duration.inSeconds;
    final cues = <ScheduledCue>[
      ScheduledCue(
        offset: Duration.zero,
        priority: CuePriority.critical,
        sound: CueSound.endBell,
        speech: _restOpening(segment),
      ),
    ];

    if (next != null) {
      final previewOffset = seconds >= 40
          ? Duration(seconds: seconds - 30)
          : Duration(seconds: (seconds / 2).round());
      cues.add(
        ScheduledCue(
          offset: previewOffset,
          priority: CuePriority.important,
          speech: _preview(next),
        ),
      );
    }

    if (seconds >= 25 && next != null) {
      cues.add(
        ScheduledCue(
          offset: Duration(seconds: seconds - 10),
          priority: CuePriority.important,
          sound: CueSound.warning,
          speech: _variant(const <String>[
            'Ten seconds. Hands up.',
            'Ten seconds. Back in stance.',
            'Ten seconds. Ready.',
          ], segment.index),
        ),
      );
    }

    return cues;
  }

  static String _restOpening(SessionSegment segment) {
    final parts = <String>[
      _variant(const <String>[
        'Rest. Breathe.',
        'Rest. Water if you need it.',
        'Rest. Slow the breathing down.',
      ], segment.index),
    ];
    if (segment.isLastOfPhase) {
      parts.add('That is the ${segment.phase.label.toLowerCase()} done.');
    }
    return parts.join(' ');
  }

  static String _preview(SessionSegment next) {
    if (!next.isWork) return 'Rest coming up.';

    final parts = <String>['Get ready.'];
    if (next.isFirstOfPhase) {
      parts.add('${next.phase.label} next.');
      parts.add('${next.title}.');
    } else if (next.roundNumber != null) {
      parts.add('Next round is ${_lowerFirst(next.title)}.');
    } else {
      parts.add('Next up: ${_lowerFirst(next.title)}.');
    }

    final hint = _previewHint(next.exercise);
    if (hint != null) parts.add(hint);
    return parts.join(' ');
  }

  static String? _previewHint(Exercise exercise) =>
      exercise.cues.isEmpty ? null : exercise.cues.last;

  // ----------------------------------------------------------------- utils

  /// The first work segment that begins at or past the session's midpoint.
  static int? _sessionHalfwaySegment(SessionPlan plan) {
    if (plan.segments.length < 6) return null;
    final midpoint = plan.totalDuration ~/ 2;
    for (final segment in plan.segments) {
      if (segment.isWork && segment.startOffset >= midpoint) {
        return segment.index;
      }
    }
    return null;
  }

  /// Deterministic variation: the coach does not repeat itself word for word,
  /// but the same plan still produces the same script every run.
  static String _variant(List<String> options, int seed) =>
      options[seed.abs() % options.length];

  static String _lowerFirst(String text) =>
      text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);

  static String _joinWords(List<String> words) {
    if (words.length <= 1) return words.join();
    return '${words.sublist(0, words.length - 1).join(', ')} '
        'and ${words.last}';
  }
}
