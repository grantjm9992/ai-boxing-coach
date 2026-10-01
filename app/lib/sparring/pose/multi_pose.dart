import 'dart:math' as math;

import 'package:sparring_pose/sparring_pose.dart';

import '../../analysis/landmarks.dart';
import '../../analysis/pose.dart';

/// Multi-person pose data for sparring: every body detected in a frame, in no
/// particular order and with no identity, plus the per-body evidence the
/// tracker needs (box, hip centre, scale, shape, appearance, facing).
///
/// Pure Dart, no plugin calls, so the tracker is unit-tested on synthetic
/// frames.

/// An axis-aligned box in image-normalised coordinates.
class PoseBox {
  const PoseBox(this.x0, this.y0, this.x1, this.y1);

  final double x0;
  final double y0;
  final double x1;
  final double y1;

  double get width => math.max(0, x1 - x0);
  double get height => math.max(0, y1 - y0);
  double get area => width * height;
  double get centerX => (x0 + x1) / 2;
  double get centerY => (y0 + y1) / 2;

  /// Intersection over union with [other] (0 when either is empty).
  double iou(PoseBox other) {
    final ix = math.min(x1, other.x1) - math.max(x0, other.x0);
    final iy = math.min(y1, other.y1) - math.max(y0, other.y0);
    if (ix <= 0 || iy <= 0) return 0;
    final inter = ix * iy;
    final union = area + other.area - inter;
    return union <= 0 ? 0 : inter / union;
  }

  List<double> toList() => <double>[x0, y0, x1, y1];
}

/// Visibility a landmark needs to count towards the box, shape and quality.
const double kCandidateMinVisibility = 0.3;

/// One detected body in one frame.
class PoseCandidate {
  PoseCandidate({required this.keypoints, List<double>? appearance})
    : appearance = appearance ?? List<double>.filled(kAppearanceBins * 2, 0);

  /// The landmarks the engine models, as [PoseFrame] keypoints.
  final Map<Landmark, Keypoint> keypoints;

  /// Torso then shorts colour histogram (see the `sparring_pose` package).
  final List<double> appearance;

  Keypoint? _visible(Landmark landmark) {
    final kp = keypoints[landmark];
    return kp != null && kp.visibility >= kCandidateMinVisibility ? kp : null;
  }

  /// Box around the visible landmarks; empty when none are visible.
  late final PoseBox box = _box();

  PoseBox _box() {
    var x0 = double.infinity, y0 = double.infinity;
    var x1 = double.negativeInfinity, y1 = double.negativeInfinity;
    for (final kp in keypoints.values) {
      if (kp.visibility < kCandidateMinVisibility) continue;
      x0 = math.min(x0, kp.x);
      y0 = math.min(y0, kp.y);
      x1 = math.max(x1, kp.x);
      y1 = math.max(y1, kp.y);
    }
    if (!x0.isFinite) return const PoseBox(0, 0, 0, 0);
    return PoseBox(x0, y0, x1, y1);
  }

  /// Mean visibility of the shoulders and hips — how solid this body is.
  late final double quality = _quality();

  double _quality() {
    const core = <Landmark>[
      Landmark.leftShoulder,
      Landmark.rightShoulder,
      Landmark.leftHip,
      Landmark.rightHip,
    ];
    var sum = 0.0;
    for (final lm in core) {
      sum += keypoints[lm]?.visibility ?? 0;
    }
    return sum / core.length;
  }

  List<double>? _mid(Landmark a, Landmark b) {
    final ka = _visible(a);
    final kb = _visible(b);
    if (ka != null && kb != null) return <double>[(ka.x + kb.x) / 2, (ka.y + kb.y) / 2];
    final one = ka ?? kb;
    return one == null ? null : <double>[one.x, one.y];
  }

  /// Hip centre (falls back to one hip), or null.
  late final List<double>? hip = _mid(Landmark.leftHip, Landmark.rightHip);

  late final List<double>? shoulders =
      _mid(Landmark.leftShoulder, Landmark.rightShoulder);

  /// Shoulder-centre to hip-centre length — the scale unit, as in the
  /// single-person engine. 0 when unknown.
  late final double torso = _torso();

  double _torso() {
    final s = shoulders;
    final h = hip;
    if (s == null || h == null) return 0;
    return _dist(s, h);
  }

  /// Scale-free body shape: upper arm, forearm, thigh and shin lengths over
  /// the torso, each the longer of the visible sides (side-on, the far limb is
  /// the foreshortened, half-hidden one). NaN where unknown. Bodies differ
  /// here and clothes don't change it.
  late final List<double> shape = _shape();

  List<double> _shape() {
    final t = torso;
    if (t <= 0) return List<double>.filled(4, double.nan);
    double limb(Landmark a, Landmark b, Landmark c, Landmark d) {
      final lengths = <double>[];
      final ka = _visible(a), kb = _visible(b);
      if (ka != null && kb != null) lengths.add(_dist(ka.xy, kb.xy));
      final kc = _visible(c), kd = _visible(d);
      if (kc != null && kd != null) lengths.add(_dist(kc.xy, kd.xy));
      if (lengths.isEmpty) return double.nan;
      return lengths.reduce(math.max) / t;
    }

    return <double>[
      limb(Landmark.leftShoulder, Landmark.leftElbow,
          Landmark.rightShoulder, Landmark.rightElbow),
      limb(Landmark.leftElbow, Landmark.leftWrist,
          Landmark.rightElbow, Landmark.rightWrist),
      limb(Landmark.leftHip, Landmark.leftKnee,
          Landmark.rightHip, Landmark.rightKnee),
      limb(Landmark.leftKnee, Landmark.leftAnkle,
          Landmark.rightKnee, Landmark.rightAnkle),
    ];
  }

  /// Which way the body faces in the image: +1 right, -1 left, 0 unclear.
  /// Side-on, the nose sits ahead of the ears.
  late final int facing = _facing();

  int _facing() {
    final nose = _visible(Landmark.nose);
    final ears = _mid(Landmark.leftEar, Landmark.rightEar) ?? shoulders;
    if (nose == null || ears == null || torso <= 0) return 0;
    final dx = nose.x - ears[0];
    if (dx.abs() < 0.12 * torso) return 0;
    return dx > 0 ? 1 : -1;
  }

  /// The frame this body would be if it were the only one — what the
  /// single-person analysis code consumes.
  PoseFrame toFrame(int index, double timestampMs) =>
      PoseFrame(index: index, timestampMs: timestampMs, keypoints: keypoints);

  static double _dist(List<double> a, List<double> b) {
    final dx = a[0] - b[0];
    final dy = a[1] - b[1];
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Compact wire form: the modelled landmarks in [Landmark.values] order as a
  /// flat `[x, y, z, v, …]` list (4 decimals), and the appearance (3).
  Map<String, Object?> toJson() => <String, Object?>{
    'k': <double>[
      for (final lm in Landmark.values) ..._kp(keypoints[lm]),
    ],
    'a': <double>[for (final v in appearance) _round(v, 1000)],
  };

  static List<double> _kp(Keypoint? kp) => kp == null
      ? const <double>[0, 0, 0, 0]
      : <double>[
          _round(kp.x, 10000),
          _round(kp.y, 10000),
          _round(kp.z, 10000),
          _round(kp.visibility, 10000),
        ];

  static double _round(double v, int scale) => (v * scale).round() / scale;

  factory PoseCandidate.fromJson(Map<String, Object?> json) {
    final flat = (json['k'] as List<Object?>? ?? const <Object?>[])
        .map((v) => (v as num).toDouble())
        .toList();
    final keypoints = <Landmark, Keypoint>{};
    for (var i = 0; i < Landmark.values.length; i++) {
      if (flat.length < (i + 1) * 4) break;
      final v = flat[i * 4 + 3];
      if (v <= 0) continue;
      keypoints[Landmark.values[i]] =
          Keypoint(flat[i * 4], flat[i * 4 + 1], z: flat[i * 4 + 2], visibility: v);
    }
    return PoseCandidate(
      keypoints: keypoints,
      appearance: <double>[
        for (final v in (json['a'] as List<Object?>? ?? const <Object?>[]))
          (v as num).toDouble(),
      ],
    );
  }

  /// From the native plugin's raw body (all 33 MediaPipe landmarks).
  factory PoseCandidate.fromRaw(RawPoseCandidate raw) {
    final keypoints = <Landmark, Keypoint>{};
    for (final lm in Landmark.values) {
      final i = lm.mpIndex;
      keypoints[lm] = Keypoint(raw.x(i), raw.y(i), z: raw.z(i), visibility: raw.visibility(i));
    }
    return PoseCandidate(
      keypoints: keypoints,
      appearance: <double>[for (final v in raw.appearance) v],
    );
  }
}

/// Every body detected in one sampled frame.
class MultiPoseFrame {
  const MultiPoseFrame({
    required this.index,
    required this.timestampMs,
    required this.candidates,
  });

  final int index;
  final double timestampMs;
  final List<PoseCandidate> candidates;

  Map<String, Object?> toJson() => <String, Object?>{
    'i': index,
    't': timestampMs,
    'p': <Object?>[for (final c in candidates) c.toJson()],
  };

  factory MultiPoseFrame.fromJson(Map<String, Object?> json) => MultiPoseFrame(
    index: (json['i'] as num).toInt(),
    timestampMs: (json['t'] as num).toDouble(),
    candidates: <PoseCandidate>[
      for (final c in (json['p'] as List<Object?>? ?? const <Object?>[]))
        PoseCandidate.fromJson((c as Map).cast<String, Object?>()),
    ],
  );

  factory MultiPoseFrame.fromRaw(RawMultiPoseFrame raw) => MultiPoseFrame(
    index: raw.index,
    timestampMs: raw.timestampMs,
    candidates: <PoseCandidate>[
      for (final p in raw.poses) PoseCandidate.fromRaw(p),
    ],
  );
}

/// A whole round's multi-pose frames plus the sampling rate.
class MultiPoseRound {
  const MultiPoseRound({required this.frames, required this.fps});

  final List<MultiPoseFrame> frames;
  final double fps;

  double get durationMs =>
      frames.isEmpty ? 0 : frames.last.timestampMs - frames.first.timestampMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'fps': fps,
    'frames': <Object?>[for (final f in frames) f.toJson()],
  };

  factory MultiPoseRound.fromJson(Map<String, Object?> json) => MultiPoseRound(
    fps: (json['fps'] as num).toDouble(),
    frames: <MultiPoseFrame>[
      for (final f in (json['frames'] as List<Object?>))
        MultiPoseFrame.fromJson((f as Map).cast<String, Object?>()),
    ],
  );
}
