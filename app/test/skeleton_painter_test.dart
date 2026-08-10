import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/ui/widgets/skeleton_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PoseFrame _frame() => PoseFrame(
  index: 0,
  timestampMs: 0,
  keypoints: <Landmark, Keypoint>{
    Landmark.leftShoulder: const Keypoint(0.42, 0.40),
    Landmark.rightShoulder: const Keypoint(0.58, 0.40),
    Landmark.leftHip: const Keypoint(0.44, 0.60),
    Landmark.rightHip: const Keypoint(0.56, 0.60),
    Landmark.leftWrist: const Keypoint(0.30, 0.38),
    // A faint landmark that should be skipped, not drawn.
    Landmark.rightWrist: const Keypoint(0.70, 0.38, visibility: 0.1),
  },
);

void main() {
  testWidgets('SkeletonOverlay renders a frame without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 300,
            child: SkeletonOverlay(
              frame: _frame(),
              highlight: const <Landmark>{Landmark.leftWrist},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(SkeletonOverlay), findsOneWidget);
  });

  testWidgets('SkeletonOverlay tolerates a null frame', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SkeletonOverlay(frame: null)),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('frameAtTimestamp finds the nearest frame', () {
    final seq = PoseSequence(
      frames: <PoseFrame>[
        PoseFrame(index: 0, timestampMs: 0, keypoints: const {}),
        PoseFrame(index: 1, timestampMs: 100, keypoints: const {}),
        PoseFrame(index: 2, timestampMs: 200, keypoints: const {}),
      ],
      fps: 30,
    );
    expect(seq.frameAtTimestamp(90)?.index, 1);
    expect(seq.frameAtTimestamp(0)?.index, 0);
    expect(seq.frameAtTimestamp(1000)?.index, 2);
  });
}
