import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Sparring mode's pose extraction: every body MediaPipe detects in each
/// sampled frame of a recorded clip, with an appearance descriptor per body.
///
/// Deliberately separate from `pose_landmarker` (one body per frame), which the
/// single-person pipeline uses and which sparring never touches. The output is
/// estimator-raw and **unordered**: bodies come in no particular order and with
/// no identity. Working out who is who is the app's tracker's job.

/// Landmarks per body (MediaPipe Pose).
const int kSparringLandmarkCount = 33;

/// Bins per appearance histogram; a descriptor holds two (torso, shorts).
const int kAppearanceBins = 11;

/// One detected body in one frame.
class RawPoseCandidate {
  RawPoseCandidate({required this.landmarks, required this.appearance});

  /// x, y, z, visibility per landmark, MediaPipe order:
  /// `[x0, y0, z0, v0, x1, …]`, length 33 × 4.
  final Float32List landmarks;

  /// Torso histogram then shorts histogram, [kAppearanceBins] each. Bins 0–7
  /// are hue, 8 black, 9 grey, 10 white. A histogram is all zero when its
  /// region wasn't visible.
  final Float32List appearance;

  double x(int i) => landmarks[i * 4];
  double y(int i) => landmarks[i * 4 + 1];
  double z(int i) => landmarks[i * 4 + 2];
  double visibility(int i) => landmarks[i * 4 + 3];

  factory RawPoseCandidate.fromMap(Map<Object?, Object?> map) =>
      RawPoseCandidate(
        landmarks: _floats(map['lm'], kSparringLandmarkCount * 4),
        appearance: _floats(map['app'], kAppearanceBins * 2),
      );

  static Float32List _floats(Object? raw, int length) {
    final out = Float32List(length);
    if (raw is List) {
      for (var i = 0; i < raw.length && i < length; i++) {
        final v = raw[i];
        if (v is num) out[i] = v.toDouble();
      }
    }
    return out;
  }
}

/// Every body detected in one sampled frame.
class RawMultiPoseFrame {
  RawMultiPoseFrame({
    required this.index,
    required this.timestampMs,
    required this.poses,
  });

  final int index;
  final double timestampMs;
  final List<RawPoseCandidate> poses;

  factory RawMultiPoseFrame.fromMap(Map<Object?, Object?> map) =>
      RawMultiPoseFrame(
        index: (map['i'] as num).toInt(),
        timestampMs: (map['t'] as num).toDouble(),
        poses: <RawPoseCandidate>[
          for (final p in (map['poses'] as List<Object?>? ?? const <Object?>[]))
            if (p is Map) RawPoseCandidate.fromMap(p),
        ],
      );
}

/// One event of an extraction run: progress, plus the frames decoded since
/// the last event.
class SparringExtractionEvent {
  const SparringExtractionEvent({
    required this.framesProcessed,
    required this.totalFrames,
    this.frames = const <RawMultiPoseFrame>[],
    this.reset = false,
    this.done = false,
  });

  final int framesProcessed;
  final int totalFrames;

  /// The next batch of frames, in order.
  final List<RawMultiPoseFrame> frames;

  /// The native side restarted with its fallback decoder: drop every frame
  /// received so far.
  final bool reset;

  /// The run finished; no more frames follow.
  final bool done;

  double get fraction =>
      totalFrames == 0 ? 0 : (framesProcessed / totalFrames).clamp(0.0, 1.0);

  factory SparringExtractionEvent.fromMap(Map<Object?, Object?> map) =>
      SparringExtractionEvent(
        framesProcessed: (map['framesProcessed'] as num?)?.toInt() ?? 0,
        totalFrames: (map['totalFrames'] as num?)?.toInt() ?? 0,
        frames: <RawMultiPoseFrame>[
          for (final f in (map['frames'] as List<Object?>? ?? const <Object?>[]))
            if (f is Map) RawMultiPoseFrame.fromMap(f),
        ],
        reset: map['reset'] == true,
        done: map['done'] == true,
      );
}

/// Thrown when extraction can't run — model missing, decode failure, or no
/// platform implementation.
class SparringPoseException implements Exception {
  const SparringPoseException(this.message);
  final String message;
  @override
  String toString() => 'SparringPoseException: $message';
}

/// Runs multi-person pose extraction over a recorded clip.
class SparringPoseExtractor {
  SparringPoseExtractor({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel('sparring_pose/methods'),
      _events = events ?? const EventChannel('sparring_pose/progress');

  final MethodChannel _methods;
  final EventChannel _events;

  /// Extracts every body from the clip at [videoPath], one frame every
  /// [sampleEvery], with the `.task` model at [modelPath]. [maxPoses] is how
  /// many bodies MediaPipe may return per frame — more than the two fighters,
  /// so a bystander can't take a fighter's slot.
  Stream<SparringExtractionEvent> extract(
    String videoPath, {
    required String modelPath,
    Duration sampleEvery = const Duration(milliseconds: 50),
    int maxPoses = 3,
  }) {
    final args = <String, Object?>{
      'videoPath': videoPath,
      'modelPath': modelPath,
      'sampleEveryMs': sampleEvery.inMilliseconds,
      'maxPoses': maxPoses,
    };
    final controller = StreamController<SparringExtractionEvent>();
    StreamSubscription<Object?>? sub;

    controller.onListen = () {
      sub = _events.receiveBroadcastStream(args).listen(
        (event) {
          if (event is! Map) return;
          final parsed = SparringExtractionEvent.fromMap(event);
          controller.add(parsed);
          if (parsed.done) controller.close();
        },
        onError: (Object error) {
          controller.addError(
            SparringPoseException(error is PlatformException
                ? (error.message ?? error.code)
                : '$error'),
          );
          controller.close();
        },
        onDone: controller.close,
      );
    };
    controller.onCancel = () async {
      await sub?.cancel();
      try {
        await _methods.invokeMethod<void>('cancel');
      } on PlatformException {
        // Nothing to cancel.
      } on MissingPluginException {
        // No platform implementation (tests, desktop).
      }
    };
    return controller.stream;
  }
}
