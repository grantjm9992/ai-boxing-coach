import '../engine/coach_cue.dart';

/// Everything the coach can make come out of the phone.
///
/// The engine talks to this interface only, so the timer and cue logic have no
/// dependency on text-to-speech or audio plugins — that is what lets the whole
/// session engine run in a plain Dart test with [SilentCoachVoice].
abstract class CoachVoice {
  /// Speaks [text]. Implementations decide what happens when a cue arrives
  /// while another is still being spoken; the contract is that a
  /// [CuePriority.critical] cue is never dropped and a [CuePriority.routine]
  /// one never interrupts.
  Future<void> speak(String text, CuePriority priority);

  Future<void> playSound(CueSound sound);

  /// Stops anything in progress — used on pause and when leaving a session.
  Future<void> silence();

  Future<void> dispose();
}

/// Does nothing, remembers everything. Used in tests and as the fallback when
/// audio is unavailable.
class SilentCoachVoice implements CoachVoice {
  final List<String> spoken = <String>[];
  final List<CueSound> sounds = <CueSound>[];
  int silenceCount = 0;

  @override
  Future<void> speak(String text, CuePriority priority) async {
    spoken.add(text);
  }

  @override
  Future<void> playSound(CueSound sound) async {
    sounds.add(sound);
  }

  @override
  Future<void> silence() async {
    silenceCount++;
  }

  @override
  Future<void> dispose() async {}
}
