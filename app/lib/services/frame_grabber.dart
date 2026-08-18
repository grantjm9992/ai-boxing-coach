import 'dart:typed_data';

import 'package:pose_landmarker/pose_landmarker.dart';

import 'ai/vision_model.dart';

/// Pulls specific frames out of a clip as images, for the AI coaching modes.
/// An interface so the coaching pipeline can be tested with a fake, and so a
/// no-camera platform degrades cleanly.
abstract class FrameGrabber {
  /// A [VisionImage] for each timestamp (ms) that could be decoded, in order.
  Future<List<VisionImage>> grab(String videoPath, List<double> timestampsMs);
}

/// Real grabber, backed by the `pose_landmarker` plugin.
class PluginFrameGrabber implements FrameGrabber {
  PluginFrameGrabber({PoseLandmarker? landmarker})
    : _landmarker = landmarker ?? PoseLandmarker();

  final PoseLandmarker _landmarker;

  @override
  Future<List<VisionImage>> grab(
    String videoPath,
    List<double> timestampsMs,
  ) async {
    if (timestampsMs.isEmpty) return const <VisionImage>[];
    final List<Uint8List> jpegs = await _landmarker.grabFrames(
      videoPath,
      timestampsMs.map((t) => t.round()).toList(),
    );
    return <VisionImage>[for (final bytes in jpegs) VisionImage(bytes: bytes)];
  }
}

/// Returns canned frames; records what was asked for. The test double.
class FakeFrameGrabber implements FrameGrabber {
  FakeFrameGrabber({Uint8List? bytes})
    : _bytes = bytes ?? Uint8List.fromList(<int>[1, 2, 3]);

  final Uint8List _bytes;
  final List<List<double>> calls = <List<double>>[];

  @override
  Future<List<VisionImage>> grab(
    String videoPath,
    List<double> timestampsMs,
  ) async {
    calls.add(timestampsMs);
    return <VisionImage>[
      for (final _ in timestampsMs) VisionImage(bytes: _bytes),
    ];
  }
}
