import 'dart:async';

import 'package:flutter/services.dart';

/// A thin Dart surface over MediaPipe Tasks Vision Pose Landmarker.
///
/// The whole point (see docs/v0.5-pose-integration.md §1) is that this stays
/// tiny — one method — and keeps everything native behind it: decoding,
/// timestamping, model loading, GPU/CPU delegate selection. It runs over a
/// *recorded file*, not a live stream, because the spec's flow analyses during
/// the rest period, not in real time.
///
/// The output is estimator-raw: 33 MediaPipe landmarks per frame, indices and
/// coordinate convention exactly as MediaPipe emits them. The app maps that into
/// its own `PoseSequence` (which keeps only the landmarks the rules use).

enum PoseModel {
  /// `pose_landmarker_lite.task` (~6 MB) — the default.
  lite,

  /// `pose_landmarker_full.task` (~9 MB) — a device-tier upgrade.
  full,
}

/// One raw landmark, in MediaPipe's normalised image coordinates.
class RawLandmark {
  const RawLandmark(this.x, this.y, this.z, this.visibility);

  final double x;
  final double y;
  final double z;
  final double visibility;

  factory RawLandmark.fromList(List<Object?> v) => RawLandmark(
    (v[0] as num).toDouble(),
    (v[1] as num).toDouble(),
    (v[2] as num).toDouble(),
    (v[3] as num).toDouble(),
  );
}

/// The 33 landmarks detected in one sampled frame (empty if none detected).
class RawPoseFrame {
  const RawPoseFrame({
    required this.index,
    required this.timestampMs,
    required this.landmarks,
  });

  final int index;
  final double timestampMs;
  final List<RawLandmark> landmarks;

  factory RawPoseFrame.fromMap(Map<Object?, Object?> map) => RawPoseFrame(
    index: (map['i'] as num).toInt(),
    timestampMs: (map['t'] as num).toDouble(),
    landmarks: <RawLandmark>[
      for (final lm in (map['lm'] as List<Object?>))
        RawLandmark.fromList(lm as List<Object?>),
    ],
  );
}

/// Progress while estimating, and — on the final event — the whole sequence.
class PoseEstimationProgress {
  const PoseEstimationProgress({
    required this.framesProcessed,
    required this.totalFrames,
    this.frames,
  });

  final int framesProcessed;
  final int totalFrames;

  /// Non-null only on the final event: every sampled frame's landmarks.
  final List<RawPoseFrame>? frames;

  bool get isDone => frames != null;

  double get fraction =>
      totalFrames == 0 ? 0 : (framesProcessed / totalFrames).clamp(0.0, 1.0);
}

/// Thrown when estimation can't run — model missing, decode failure, or the
/// platform has no implementation (desktop/web).
class PoseEstimationException implements Exception {
  const PoseEstimationException(this.message);
  final String message;
  @override
  String toString() => 'PoseEstimationException: $message';
}

/// Runs pose estimation over a recorded clip. The one method the app needs.
class PoseLandmarker {
  PoseLandmarker({MethodChannel? channel, EventChannel? events})
    : _method = channel ?? const MethodChannel('pose_landmarker/methods'),
      _events = events ?? const EventChannel('pose_landmarker/progress');

  final MethodChannel _method;
  final EventChannel _events;

  /// Estimates pose over the clip at [videoPath], sampling one frame every
  /// [sampleEvery] (default ~30fps). [modelPath] is an absolute path to the
  /// `.task` model file the app has provisioned (see PoseModelProvisioner);
  /// [model] selects which the app expects it to be.
  ///
  /// Emits progress so the rest-period UI can show something moving, and a final
  /// event whose [PoseEstimationProgress.frames] is the sequence the rules
  /// consume.
  Stream<PoseEstimationProgress> estimate(
    String videoPath, {
    required String modelPath,
    Duration sampleEvery = const Duration(milliseconds: 33),
    PoseModel model = PoseModel.lite,
  }) {
    // Ask the native side to start; progress and the final result arrive on the
    // event channel keyed by this same videoPath.
    final args = <String, Object?>{
      'videoPath': videoPath,
      'modelPath': modelPath,
      'sampleEveryMs': sampleEvery.inMilliseconds,
      'model': model.name,
    };

    final controller = StreamController<PoseEstimationProgress>();
    StreamSubscription<Object?>? sub;

    controller.onListen = () async {
      sub = _events.receiveBroadcastStream(args).listen(
        (event) {
          final map = (event as Map<Object?, Object?>);
          final framesRaw = map['frames'] as List<Object?>?;
          controller.add(
            PoseEstimationProgress(
              framesProcessed: (map['framesProcessed'] as num?)?.toInt() ?? 0,
              totalFrames: (map['totalFrames'] as num?)?.toInt() ?? 0,
              frames: framesRaw == null
                  ? null
                  : <RawPoseFrame>[
                      for (final f in framesRaw)
                        RawPoseFrame.fromMap(f as Map<Object?, Object?>),
                    ],
            ),
          );
          if (framesRaw != null) controller.close();
        },
        onError: (Object error) {
          controller.addError(
            PoseEstimationException(error is PlatformException
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
      // Best-effort: tell native to stop decoding if it is still going.
      try {
        await _method.invokeMethod<void>('cancel', <String, Object?>{
          'videoPath': videoPath,
        });
      } on PlatformException {
        // Nothing to cancel.
      }
    };

    return controller.stream;
  }

  /// Grabs a JPEG for each timestamp (ms) from the clip — the frames the AI
  /// coaching modes send to the model. Orientation-correct (uses the rotating
  /// retriever path). Missing timestamps are simply omitted.
  Future<List<Uint8List>> grabFrames(
    String videoPath,
    List<int> timestampsMs,
  ) async {
    final result = await _method.invokeMethod<List<Object?>>('grabFrames', {
      'videoPath': videoPath,
      'timestampsMs': timestampsMs,
    });
    return <Uint8List>[
      for (final bytes in result ?? const <Object?>[])
        if (bytes is Uint8List) bytes,
    ];
  }
}
