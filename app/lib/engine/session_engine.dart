import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/session_phase.dart';
import '../domain/session_plan.dart';
import '../services/coach_voice.dart';
import 'coach_cue.dart';
import 'cue_scheduler.dart';

enum SessionStatus { ready, running, paused, completed }

/// Runs a [SessionPlan]: keeps the clock, walks the segments, and fires the
/// coach's script at the right moments.
///
/// Time is advanced through [advance] rather than read from the wall clock
/// inside the state machine. The real session drives it from a periodic timer
/// that measures elapsed time with a [Stopwatch] — so a slow frame delays a cue
/// but never loses one, and drift does not accumulate — while tests drive it
/// directly and deterministically.
class SessionEngine extends ChangeNotifier {
  SessionEngine({
    required this.plan,
    required this.voice,
    this.tickInterval = const Duration(milliseconds: 200),
  }) : _script = CueScheduler.schedule(plan),
       _voiceEnabled = plan.settings.voiceEnabled,
       _soundEnabled = plan.settings.soundEnabled;

  final SessionPlan plan;

  /// Where cues are delivered. Swappable so the engine can run without audio.
  final CoachVoice voice;

  /// How often the wall clock is sampled while running.
  final Duration tickInterval;
  final Map<int, List<ScheduledCue>> _script;

  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  Duration _lastTick = Duration.zero;

  SessionStatus _status = SessionStatus.ready;
  int _segmentIndex = 0;
  Duration _elapsedInSegment = Duration.zero;
  int _nextCueIndex = 0;
  CoachCue? _lastCue;
  bool _voiceEnabled;
  bool _soundEnabled;

  // ------------------------------------------------------------------ state

  SessionStatus get status => _status;
  bool get isRunning => _status == SessionStatus.running;
  bool get isCompleted => _status == SessionStatus.completed;

  int get segmentIndex => _segmentIndex;
  SessionSegment? get currentSegment => plan.segmentAt(_segmentIndex);
  SessionSegment? get nextSegment => plan.segmentAt(_segmentIndex + 1);

  /// The next segment the athlete actually works, skipping the rest between.
  SessionSegment? get nextWorkSegment {
    for (var i = _segmentIndex + 1; i < plan.segments.length; i++) {
      if (plan.segments[i].isWork) return plan.segments[i];
    }
    return null;
  }

  Duration get elapsedInSegment => _elapsedInSegment;

  Duration get remainingInSegment {
    final segment = currentSegment;
    if (segment == null) return Duration.zero;
    final remaining = segment.duration - _elapsedInSegment;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// 0..1 through the current segment.
  double get segmentProgress {
    final segment = currentSegment;
    if (segment == null || segment.duration.inMilliseconds == 0) return 1;
    return (_elapsedInSegment.inMilliseconds / segment.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  Duration get sessionElapsed {
    final segment = currentSegment;
    if (segment == null) return plan.totalDuration;
    return segment.startOffset + _elapsedInSegment;
  }

  Duration get sessionRemaining {
    final remaining = plan.totalDuration - sessionElapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  double get sessionProgress {
    if (plan.totalDuration.inMilliseconds == 0) return 1;
    return (sessionElapsed.inMilliseconds / plan.totalDuration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  SessionPhase? get currentPhase => currentSegment?.phase;

  /// The most recent cue, for the on-screen coach line.
  CoachCue? get lastCue => _lastCue;

  bool get voiceEnabled => _voiceEnabled;
  bool get soundEnabled => _soundEnabled;

  /// The cue script, exposed for tests and for the session preview screen.
  @visibleForTesting
  Map<int, List<ScheduledCue>> get script => _script;

  // ---------------------------------------------------------------- control

  void start() {
    if (_status == SessionStatus.running) return;
    if (_status == SessionStatus.completed) return;
    final wasReady = _status == SessionStatus.ready;
    _status = SessionStatus.running;
    _startTicking();
    if (wasReady) {
      // The opening cue of the first segment fires as the session starts, not
      // a tick later.
      _fireDueCues();
    }
    notifyListeners();
  }

  void pause() {
    if (_status != SessionStatus.running) return;
    _status = SessionStatus.paused;
    _stopTicking();
    unawaited(voice.silence());
    notifyListeners();
  }

  void togglePause() => isRunning ? pause() : start();

  /// Jumps to the start of the next segment, firing its opening cue.
  void skipSegment() {
    if (_status == SessionStatus.completed) return;
    if (!_moveToSegment(_segmentIndex + 1)) return;
    notifyListeners();
  }

  /// Restarts the current segment, or steps back to the previous one if the
  /// current one has only just begun.
  void previousSegment() {
    if (_status == SessionStatus.completed) return;
    final justStarted = _elapsedInSegment < const Duration(seconds: 3);
    final target = justStarted ? _segmentIndex - 1 : _segmentIndex;
    _moveToSegment(target < 0 ? 0 : target);
    notifyListeners();
  }

  void setVoiceEnabled(bool enabled) {
    _voiceEnabled = enabled;
    if (!enabled) unawaited(voice.silence());
    notifyListeners();
  }

  void setSoundEnabled(bool enabled) {
    _soundEnabled = enabled;
    notifyListeners();
  }

  /// Ends the session early. No completion cues — nothing was completed.
  void abandon() {
    _stopTicking();
    _status = SessionStatus.completed;
    unawaited(voice.silence());
    notifyListeners();
  }

  // ------------------------------------------------------------------- time

  /// Advances the session by [delta]. The only way time moves.
  @visibleForTesting
  void advance(Duration delta) {
    if (_status != SessionStatus.running || delta <= Duration.zero) return;

    var remaining = delta;
    while (remaining > Duration.zero) {
      final segment = currentSegment;
      if (segment == null) break;

      final left = segment.duration - _elapsedInSegment;
      if (remaining < left) {
        _elapsedInSegment += remaining;
        remaining = Duration.zero;
        _fireDueCues();
      } else {
        _elapsedInSegment = segment.duration;
        _fireDueCues();
        remaining -= left;
        if (!_moveToSegment(_segmentIndex + 1)) {
          remaining = Duration.zero;
        }
      }
    }
    notifyListeners();
  }

  void _startTicking() {
    _stopwatch
      ..reset()
      ..start();
    _lastTick = Duration.zero;
    _timer?.cancel();
    _timer = Timer.periodic(tickInterval, (_) {
      final now = _stopwatch.elapsed;
      final delta = now - _lastTick;
      _lastTick = now;
      advance(delta);
    });
  }

  void _stopTicking() {
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
  }

  /// Returns false when there is no such segment — which, moving forwards,
  /// means the session is over.
  bool _moveToSegment(int index) {
    if (index >= plan.segments.length) {
      _complete();
      return false;
    }
    if (index < 0) return false;
    _segmentIndex = index;
    _elapsedInSegment = Duration.zero;
    _nextCueIndex = 0;
    _fireDueCues();
    return true;
  }

  void _complete() {
    _stopTicking();
    _status = SessionStatus.completed;
    _elapsedInSegment = currentSegment?.duration ?? Duration.zero;
    for (final cue in CueScheduler.completionCues(plan)) {
      // The completion script is short and back-to-back; the voice layer
      // handles the queueing.
      _emit(CoachCue(segmentIndex: _segmentIndex, cue: cue));
    }
    notifyListeners();
  }

  void _fireDueCues() {
    final cues = _script[_segmentIndex];
    if (cues == null) return;
    while (_nextCueIndex < cues.length &&
        cues[_nextCueIndex].offset <= _elapsedInSegment) {
      _emit(CoachCue(segmentIndex: _segmentIndex, cue: cues[_nextCueIndex]));
      _nextCueIndex++;
    }
  }

  void _emit(CoachCue cue) {
    _lastCue = cue;
    final sound = cue.sound;
    if (_soundEnabled && sound != null) {
      unawaited(voice.playSound(sound));
    }
    final speech = cue.speech;
    if (_voiceEnabled && speech != null) {
      unawaited(voice.speak(speech, cue.priority));
    }
  }

  @override
  void dispose() {
    _stopTicking();
    unawaited(voice.silence());
    super.dispose();
  }
}
