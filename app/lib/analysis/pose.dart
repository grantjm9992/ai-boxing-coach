import 'landmarks.dart';

/// Pose data model — the Dart mirror of `src/boxing_coach/domain/pose.py`.
///
/// Estimator-agnostic: a [PoseSequence] is just keypoints over time, whether
/// they came from MediaPipe on the phone or a golden fixture in a test.

/// A single landmark position in image-normalised coordinates.
class Keypoint {
  const Keypoint(this.x, this.y, {this.z = 0.0, this.visibility = 1.0});

  final double x;
  final double y;
  final double z;
  final double visibility;

  /// [x, y] — the 2D position every v0.5 rule works in.
  List<double> get xy => <double>[x, y];
}

/// All landmarks detected in a single video frame, with a timestamp.
class PoseFrame {
  const PoseFrame({
    required this.index,
    required this.timestampMs,
    required this.keypoints,
  });

  final int index;
  final double timestampMs;
  final Map<Landmark, Keypoint> keypoints;

  Keypoint? get(Landmark landmark) => keypoints[landmark];

  bool has(List<Landmark> landmarks, {double minVisibility = 0.0}) =>
      landmarks.every((lm) {
        final kp = keypoints[lm];
        return kp != null && kp.visibility >= minVisibility;
      });
}

/// An ordered sequence of pose frames plus capture metadata.
class PoseSequence {
  PoseSequence({
    required this.frames,
    required this.fps,
    this.source = 'unknown',
    this.meta = const <String, Object?>{},
  }) {
    if (fps <= 0) throw ArgumentError('fps must be positive');
  }

  final List<PoseFrame> frames;
  final double fps;
  final String source;
  final Map<String, Object?> meta;

  int get length => frames.length;

  double get durationMs => frames.isEmpty
      ? 0.0
      : frames.last.timestampMs - frames.first.timestampMs;

  /// The frame whose timestamp is nearest [ms] — for syncing a skeleton overlay
  /// to the video scrub position. Null only for an empty sequence.
  PoseFrame? frameAtTimestamp(double ms) {
    if (frames.isEmpty) return null;
    var best = frames.first;
    var bestDelta = (best.timestampMs - ms).abs();
    for (final frame in frames) {
      final delta = (frame.timestampMs - ms).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = frame;
      }
    }
    return best;
  }

  /// Encodes to the wire format shared with the Python reference
  /// (`golden_fixtures.sequence_to_json`): landmark index as key, coordinates
  /// rounded to 4 decimals. Used to persist a round's poses alongside its clip.
  Map<String, Object?> toJson() => <String, Object?>{
    'fps': fps,
    'source': source,
    'meta': meta,
    'frames': <Map<String, Object?>>[
      for (final frame in frames)
        <String, Object?>{
          'i': frame.index,
          't': _round4(frame.timestampMs),
          'kp': <String, Object?>{
            for (final entry in frame.keypoints.entries)
              '${entry.key.mpIndex}': <double>[
                _round4(entry.value.x),
                _round4(entry.value.y),
                _round4(entry.value.z),
                _round4(entry.value.visibility),
              ],
          },
        },
    ],
  };

  static double _round4(double v) => (v * 10000).round() / 10000;

  /// Decodes the golden-fixture / calibration-upload wire format. Must match
  /// `golden_fixtures.sequence_to_json` on the Python side exactly.
  factory PoseSequence.fromJson(Map<String, Object?> json) {
    final frameList = (json['frames'] as List<Object?>).map((raw) {
      final frame = raw as Map<String, Object?>;
      final kpMap = frame['kp'] as Map<String, Object?>;
      final keypoints = <Landmark, Keypoint>{};
      kpMap.forEach((indexKey, valuesRaw) {
        final landmark = Landmark.fromIndex(int.parse(indexKey));
        if (landmark == null) return; // a landmark we don't model — skip it
        final values = (valuesRaw as List<Object?>)
            .map((v) => (v as num).toDouble())
            .toList();
        keypoints[landmark] = Keypoint(
          values[0],
          values[1],
          z: values.length > 2 ? values[2] : 0.0,
          visibility: values.length > 3 ? values[3] : 1.0,
        );
      });
      return PoseFrame(
        index: (frame['i'] as num).toInt(),
        timestampMs: (frame['t'] as num).toDouble(),
        keypoints: keypoints,
      );
    }).toList();

    return PoseSequence(
      frames: frameList,
      fps: (json['fps'] as num).toDouble(),
      source: json['source'] as String? ?? 'unknown',
      meta: (json['meta'] as Map<String, Object?>?) ?? const <String, Object?>{},
    );
  }
}
