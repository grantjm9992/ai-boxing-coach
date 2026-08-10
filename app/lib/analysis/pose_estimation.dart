import 'package:pose_landmarker/pose_landmarker.dart';

import 'landmarks.dart';
import 'pose.dart';

/// The pure glue between the `pose_landmarker` plugin's raw output and the
/// engine's [PoseSequence]. Kept free of plugins and platform channels so it can
/// be unit-tested without a device.

/// Landmarks that must be visible for a frame to count as "full body in frame" —
/// shoulders, hips and ankles. If these are present the rules have what they
/// need; this drives the honest "we can see you" indicator (stage 0.3).
const List<Landmark> fullBodyLandmarks = <Landmark>[
  Landmark.leftShoulder,
  Landmark.rightShoulder,
  Landmark.leftHip,
  Landmark.rightHip,
  Landmark.leftAnkle,
  Landmark.rightAnkle,
];

/// Converts the plugin's raw 33-landmark frames into a [PoseSequence], keeping
/// only the landmarks the engine models (by MediaPipe index). Frames with no
/// detection become empty frames — their timestamps still matter, and the rules
/// already treat missing landmarks as NaN.
PoseSequence rawFramesToSequence(
  List<RawPoseFrame> rawFrames, {
  required double fps,
  String source = 'mediapipe',
  Map<String, Object?> meta = const <String, Object?>{},
}) {
  final frames = <PoseFrame>[
    for (final raw in rawFrames)
      PoseFrame(
        index: raw.index,
        timestampMs: raw.timestampMs,
        keypoints: _keypoints(raw.landmarks),
      ),
  ];
  return PoseSequence(frames: frames, fps: fps, source: source, meta: meta);
}

Map<Landmark, Keypoint> _keypoints(List<RawLandmark> landmarks) {
  final out = <Landmark, Keypoint>{};
  for (var index = 0; index < landmarks.length; index++) {
    final landmark = Landmark.fromIndex(index);
    if (landmark == null) continue; // one we don't model
    final lm = landmarks[index];
    out[landmark] = Keypoint(lm.x, lm.y, z: lm.z, visibility: lm.visibility);
  }
  return out;
}

/// Fraction of frames (0..1) in which the whole body — [fullBodyLandmarks] — is
/// visible above [minVisibility]. 0 for an empty sequence.
double fullBodyVisibleFraction(
  PoseSequence sequence, {
  double minVisibility = 0.5,
}) {
  if (sequence.frames.isEmpty) return 0.0;
  var visible = 0;
  for (final frame in sequence.frames) {
    if (frame.has(fullBodyLandmarks, minVisibility: minVisibility)) visible++;
  }
  return visible / sequence.frames.length;
}
