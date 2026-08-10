import 'package:boxing_coach/analysis/features.dart';
import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/pose_estimation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pose_landmarker/pose_landmarker.dart';

/// Builds a 33-landmark frame, overriding specific MediaPipe indices. Unset
/// landmarks default to a visible point at the origin.
RawPoseFrame _frame(
  int index,
  double t,
  Map<int, RawLandmark> overrides, {
  bool empty = false,
}) {
  if (empty) return RawPoseFrame(index: index, timestampMs: t, landmarks: const []);
  final landmarks = <RawLandmark>[
    for (var i = 0; i < 33; i++)
      overrides[i] ?? const RawLandmark(0, 0, 0, 1),
  ];
  return RawPoseFrame(index: index, timestampMs: t, landmarks: landmarks);
}

// A neutral standing pose (mirrors the Python fixtures' base): torso length 0.2.
Map<int, RawLandmark> _standing({double ankleVisibility = 1.0}) => <int, RawLandmark>{
  11: const RawLandmark(0.42, 0.40, 0, 1), // left shoulder
  12: const RawLandmark(0.58, 0.40, 0, 1), // right shoulder
  23: const RawLandmark(0.44, 0.60, 0, 1), // left hip
  24: const RawLandmark(0.56, 0.60, 0, 1), // right hip
  27: RawLandmark(0.44, 0.95, 0, ankleVisibility), // left ankle
  28: RawLandmark(0.56, 0.95, 0, ankleVisibility), // right ankle
};

void main() {
  test('raw frames map to a sequence keyed by modelled landmarks', () {
    final raw = <RawPoseFrame>[
      _frame(0, 0, _standing()),
      _frame(1, 33.3, _standing()),
    ];
    final seq = rawFramesToSequence(raw, fps: 30);

    expect(seq.length, 2);
    expect(seq.fps, 30);
    final f0 = seq.frames.first;
    // Modelled landmarks are present; a non-modelled index (1) is dropped.
    expect(f0.get(Landmark.leftShoulder)?.x, closeTo(0.42, 1e-9));
    expect(f0.keypoints.containsKey(Landmark.leftShoulder), isTrue);
    expect(Landmark.fromIndex(1), isNull);
    // Body scale from the mapped sequence is the shoulder->hip distance (0.2).
    expect(computeBodyScale(seq), closeTo(0.2, 1e-9));
  });

  test('an empty (undetected) frame maps to a frame with no keypoints', () {
    final raw = <RawPoseFrame>[_frame(0, 0, const {}, empty: true)];
    final seq = rawFramesToSequence(raw, fps: 30);
    expect(seq.frames.single.keypoints, isEmpty);
  });

  group('fullBodyVisibleFraction', () {
    test('is 1.0 when every frame has the whole body visible', () {
      final seq = rawFramesToSequence(
        <RawPoseFrame>[_frame(0, 0, _standing()), _frame(1, 33, _standing())],
        fps: 30,
      );
      expect(fullBodyVisibleFraction(seq), 1.0);
    });

    test('drops frames where a key landmark is below the visibility bar', () {
      final seq = rawFramesToSequence(
        <RawPoseFrame>[
          _frame(0, 0, _standing()), // visible
          _frame(1, 33, _standing(ankleVisibility: 0.1)), // ankle too faint
        ],
        fps: 30,
      );
      expect(fullBodyVisibleFraction(seq), 0.5);
    });

    test('is 0 for an empty sequence', () {
      final seq = rawFramesToSequence(const <RawPoseFrame>[], fps: 30);
      expect(fullBodyVisibleFraction(seq), 0.0);
    });
  });
}
