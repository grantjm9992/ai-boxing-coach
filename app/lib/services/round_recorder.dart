/// Records a single round to a file, and nothing else.
///
/// The session logic talks to this interface only — never to the `camera`
/// plugin directly — for the same reason the coach talks to [CoachVoice] and
/// not to text-to-speech: it lets the round-recording orchestration
/// ([RoundRecordingController]) run in a plain Dart test with
/// [FakeRoundRecorder], with no camera, no permissions, and no device.
abstract class RoundRecorder {
  /// Acquires the camera. Safe to call more than once; the second call is a
  /// no-op. Throws [RecorderUnavailable] if there is no usable camera or
  /// permission was refused.
  Future<void> initialize();

  bool get isReady;

  /// Begins recording. Assumes [initialize] has completed.
  Future<void> startRecording();

  /// Stops recording and returns the path of the temporary file the camera
  /// wrote, or null if nothing was recording or the stop failed. The caller
  /// moves that file to its permanent home.
  Future<String?> stopRecording();

  bool get isRecording;

  Future<void> dispose();
}

/// Thrown when the camera cannot be used — no device, or permission refused.
/// The camera-check screen turns this into guidance rather than a crash.
class RecorderUnavailable implements Exception {
  const RecorderUnavailable(this.message);
  final String message;
  @override
  String toString() => 'RecorderUnavailable: $message';
}

/// Records nothing, remembers everything. The test double, and the fallback on
/// platforms with no camera (desktop, a simulator without one).
class FakeRoundRecorder implements RoundRecorder {
  FakeRoundRecorder({this.available = true, this.tempPath = '/tmp/fake.mp4'});

  /// When false, [initialize] throws [RecorderUnavailable].
  final bool available;

  /// The path handed back from [stopRecording].
  final String tempPath;

  final List<String> events = <String>[];
  bool _ready = false;
  bool _recording = false;

  @override
  Future<void> initialize() async {
    if (!available) throw const RecorderUnavailable('no camera in test');
    _ready = true;
    events.add('initialize');
  }

  @override
  bool get isReady => _ready;

  @override
  Future<void> startRecording() async {
    _recording = true;
    events.add('start');
  }

  @override
  Future<String?> stopRecording() async {
    if (!_recording) return null;
    _recording = false;
    events.add('stop');
    return tempPath;
  }

  @override
  bool get isRecording => _recording;

  @override
  Future<void> dispose() async {
    _recording = false;
    _ready = false;
    events.add('dispose');
  }
}
