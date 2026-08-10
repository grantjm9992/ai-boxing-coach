import 'package:flutter/material.dart';

import '../../analysis/landmarks.dart';
import '../../analysis/pose.dart';
import '../theme.dart';

/// Draws a pose skeleton over its parent, from a normalised [PoseFrame].
///
/// Stage 0.3's "we can see you" overlay: the estimated landmarks drawn on the
/// review frame. It stays a *display* layer over the clean video — never baked
/// into stored pixels — which matters for the spec's later note about sending
/// clean frames plus pose-as-text to a model (v0.8).
class SkeletonPainter extends CustomPainter {
  SkeletonPainter({
    required this.frame,
    this.minVisibility = 0.5,
    this.highlight = const <Landmark>{},
  });

  final PoseFrame? frame;
  final double minVisibility;

  /// Landmarks to emphasise (e.g. the wrist a correction is about).
  final Set<Landmark> highlight;

  /// The bones we draw — pairs of the landmarks the engine models.
  static const List<(Landmark, Landmark)> _bones = <(Landmark, Landmark)>[
    (Landmark.leftShoulder, Landmark.rightShoulder),
    (Landmark.leftHip, Landmark.rightHip),
    (Landmark.leftShoulder, Landmark.leftHip),
    (Landmark.rightShoulder, Landmark.rightHip),
    (Landmark.leftShoulder, Landmark.leftElbow),
    (Landmark.leftElbow, Landmark.leftWrist),
    (Landmark.rightShoulder, Landmark.rightElbow),
    (Landmark.rightElbow, Landmark.rightWrist),
    (Landmark.leftHip, Landmark.leftKnee),
    (Landmark.leftKnee, Landmark.leftAnkle),
    (Landmark.rightHip, Landmark.rightKnee),
    (Landmark.rightKnee, Landmark.rightAnkle),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final frame = this.frame;
    if (frame == null) return;

    final bonePaint = Paint()
      ..color = AppTheme.rest.withValues(alpha: 0.9)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final jointPaint = Paint()..color = Colors.white;
    final highlightPaint = Paint()..color = AppTheme.accent;

    Offset? at(Landmark lm) {
      final kp = frame.get(lm);
      if (kp == null || kp.visibility < minVisibility) return null;
      return Offset(kp.x * size.width, kp.y * size.height);
    }

    for (final (a, b) in _bones) {
      final pa = at(a);
      final pb = at(b);
      if (pa != null && pb != null) canvas.drawLine(pa, pb, bonePaint);
    }

    for (final landmark in Landmark.values) {
      final p = at(landmark);
      if (p == null) continue;
      final isHot = highlight.contains(landmark);
      canvas.drawCircle(p, isHot ? 7 : 4, isHot ? highlightPaint : jointPaint);
    }
  }

  @override
  bool shouldRepaint(SkeletonPainter old) =>
      old.frame != frame ||
      old.minVisibility != minVisibility ||
      old.highlight != highlight;
}

/// A convenience widget: the skeleton painted to fill its box.
class SkeletonOverlay extends StatelessWidget {
  const SkeletonOverlay({
    required this.frame,
    this.highlight = const <Landmark>{},
    super.key,
  });

  final PoseFrame? frame;
  final Set<Landmark> highlight;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: SkeletonPainter(frame: frame, highlight: highlight),
    size: Size.infinite,
  );
}
