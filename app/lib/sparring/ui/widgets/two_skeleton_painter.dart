import 'package:flutter/material.dart';

import '../../../analysis/landmarks.dart';
import '../../../analysis/pose.dart';
import '../../model/fighter.dart';
import '../../pose/multi_pose.dart';

/// Colour per fighter: A (the user, once identified) in the app accent, B in
/// blue. Used for skeletons, chips and tabs so who's who is never in doubt.
Color fighterColor(FighterLabel label) =>
    label == FighterLabel.a ? const Color(0xFFE8503A) : const Color(0xFF3D9BE8);

/// Draws both fighters' skeletons over the video, colour-coded, with an
/// optional dashed box (the body "Check who's who" is asking about).
class TwoSkeletonPainter extends CustomPainter {
  TwoSkeletonPainter({
    required this.frames,
    this.visible = const <FighterLabel>{FighterLabel.a, FighterLabel.b},
    this.labels = const <FighterLabel, String>{},
    this.question,
    this.minVisibility = 0.4,
  });

  final Map<FighterLabel, PoseFrame?> frames;
  final Set<FighterLabel> visible;

  /// Text drawn above each skeleton ("You", "Partner", "A"…).
  final Map<FighterLabel, String> labels;

  /// A box to outline (normalised).
  final PoseBox? question;
  final double minVisibility;

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
    for (final label in FighterLabel.values) {
      if (!visible.contains(label)) continue;
      final frame = frames[label];
      if (frame == null || frame.keypoints.isEmpty) continue;
      final color = fighterColor(label);
      final bone = Paint()
        ..color = color.withValues(alpha: 0.9)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final joint = Paint()..color = Colors.white;

      Offset? at(Landmark lm) {
        final kp = frame.get(lm);
        if (kp == null || kp.visibility < minVisibility) return null;
        return Offset(kp.x * size.width, kp.y * size.height);
      }

      for (final (a, b) in _bones) {
        final pa = at(a), pb = at(b);
        if (pa != null && pb != null) canvas.drawLine(pa, pb, bone);
      }
      for (final lm in Landmark.values) {
        final p = at(lm);
        if (p != null) canvas.drawCircle(p, 3, joint);
      }

      final text = labels[label];
      if (text != null) {
        final box = PoseCandidate(keypoints: frame.keypoints).box;
        if (box.area > 0) {
          final painter = TextPainter(
            text: TextSpan(
              text: ' $text ',
              style: TextStyle(
                color: Colors.white,
                backgroundColor: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final x = (box.centerX * size.width - painter.width / 2)
              .clamp(0.0, size.width - painter.width)
              .toDouble();
          final y = (box.y0 * size.height - painter.height - 4)
              .clamp(0.0, size.height - painter.height)
              .toDouble();
          painter.paint(canvas, Offset(x, y));
        }
      }
    }

    final q = question;
    if (q != null) {
      final rect = Rect.fromLTRB(
        q.x0 * size.width - 8,
        q.y0 * size.height - 8,
        q.x1 * size.width + 8,
        q.y1 * size.height + 8,
      );
      final paint = Paint()
        ..color = Colors.yellowAccent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      const dash = 8.0;
      for (final side in <(Offset, Offset)>[
        (rect.topLeft, rect.topRight),
        (rect.topRight, rect.bottomRight),
        (rect.bottomRight, rect.bottomLeft),
        (rect.bottomLeft, rect.topLeft),
      ]) {
        final (from, to) = side;
        final length = (to - from).distance;
        if (length == 0) continue;
        final dir = (to - from) / length;
        for (var d = 0.0; d < length; d += dash * 2) {
          final end = d + dash > length ? length : d + dash;
          canvas.drawLine(from + dir * d, from + dir * end, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(TwoSkeletonPainter old) =>
      old.frames != frames ||
      old.visible != visible ||
      old.question != question ||
      old.labels != labels;
}
