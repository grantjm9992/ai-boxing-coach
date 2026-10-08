import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../analysis/pose.dart';
import '../../model/fighter.dart';
import '../../pose/multi_pose.dart';
import '../../tracking/fighter_tracker.dart';
import 'two_skeleton_painter.dart';

/// The round's video with both fighters' skeletons kept in sync with the
/// playback position. The skeleton is a display layer over the clean video.
class SparringVideoView extends StatelessWidget {
  const SparringVideoView({
    required this.controller,
    this.tracked,
    this.visible = const <FighterLabel>{FighterLabel.a, FighterLabel.b},
    this.labels = const <FighterLabel, String>{},
    this.question,
    this.onTapFighter,
    super.key,
  });

  final VideoPlayerController controller;
  final TrackedRound? tracked;
  final Set<FighterLabel> visible;
  final Map<FighterLabel, String> labels;
  final PoseBox? question;

  /// Called with the fighter whose box was tapped (for "which one is you").
  final void Function(FighterLabel label)? onTapFighter;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          fit: StackFit.expand,
          children: <Widget>[
            VideoPlayer(controller),
            if (tracked != null)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final frames = framesAt(tracked!, value.position.inMilliseconds.toDouble());
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: onTapFighter == null
                        ? null
                        : (details) {
                            final hit = _hit(frames, details.localPosition, box.biggest);
                            if (hit != null) onTapFighter!(hit);
                          },
                    child: CustomPaint(
                      painter: TwoSkeletonPainter(
                        frames: frames,
                        visible: visible,
                        labels: labels,
                        question: question,
                      ),
                      size: Size.infinite,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Each fighter's frame nearest [ms] (video timestamps).
  static Map<FighterLabel, PoseFrame?> framesAt(TrackedRound tracked, double ms) =>
      <FighterLabel, PoseFrame?>{
        for (final label in FighterLabel.values)
          label: tracked.fighters[label]?.frameAtTimestamp(ms),
      };

  static FighterLabel? _hit(Map<FighterLabel, PoseFrame?> frames, Offset at, Size size) {
    if (size.width == 0 || size.height == 0) return null;
    final x = at.dx / size.width, y = at.dy / size.height;
    FighterLabel? best;
    var bestDistance = double.infinity;
    for (final e in frames.entries) {
      final frame = e.value;
      if (frame == null || frame.keypoints.isEmpty) continue;
      final b = PoseCandidate(keypoints: frame.keypoints).box;
      if (b.area == 0) continue;
      final inside = x >= b.x0 - 0.03 && x <= b.x1 + 0.03 && y >= b.y0 - 0.03 && y <= b.y1 + 0.03;
      final d = (x - b.centerX).abs() + (y - b.centerY).abs();
      if (inside && d < bestDistance) {
        bestDistance = d;
        best = e.key;
      }
    }
    return best;
  }
}
