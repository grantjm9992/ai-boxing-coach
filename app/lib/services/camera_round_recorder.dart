import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'round_recorder.dart';

/// The real [RoundRecorder]: a thin wrapper over a [CameraController].
///
/// Records **video only** — `enableAudio: false` — because pose analysis has no
/// use for sound and dropping it also drops the microphone permission. The
/// front camera is preferred so the camera-check preview mirrors the athlete
/// while they get themselves in frame.
class CameraRoundRecorder implements RoundRecorder {
  CameraRoundRecorder({
    this.resolution = ResolutionPreset.high,
    this.lensDirection = CameraLensDirection.front,
  });

  final ResolutionPreset resolution;
  final CameraLensDirection lensDirection;

  CameraController? _controller;

  /// Exposed so the camera-check screen can show a live [CameraPreview].
  CameraController? get controller => _controller;

  @override
  Future<void> initialize() async {
    if (_controller?.value.isInitialized ?? false) return;
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on Object catch (error) {
      // CameraException on mobile; MissingPluginException on desktop/web where
      // the plugin has no implementation. Either way: no camera here.
      throw RecorderUnavailable('$error');
    }
    if (cameras.isEmpty) {
      throw const RecorderUnavailable('This device has no camera.');
    }
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == lensDirection,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      camera,
      resolution,
      enableAudio: false,
    );
    try {
      await controller.initialize();
    } on CameraException catch (error) {
      // Permission refused surfaces here as a CameraException; treat any
      // init failure as "camera unavailable" so the UI can guide rather than
      // crash.
      throw RecorderUnavailable(error.description ?? error.code);
    }
    _controller = controller;
  }

  @override
  bool get isReady => _controller?.value.isInitialized ?? false;

  @override
  bool get isRecording => _controller?.value.isRecordingVideo ?? false;

  @override
  Future<void> startRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw const RecorderUnavailable('Camera is not ready.');
    }
    if (controller.value.isRecordingVideo) return;
    await controller.startVideoRecording();
  }

  @override
  Future<String?> stopRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isRecordingVideo) return null;
    try {
      final file = await controller.stopVideoRecording();
      return file.path;
    } on CameraException catch (error) {
      debugPrint('Stop recording failed: ${error.description}');
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    if (controller.value.isRecordingVideo) {
      try {
        await controller.stopVideoRecording();
      } on CameraException catch (_) {
        // Best effort — we are tearing down anyway.
      }
    }
    await controller.dispose();
  }
}
