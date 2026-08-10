import 'geometry.dart' as geo;
import 'landmarks.dart';
import 'pose.dart';
import 'punch.dart';
import 'punch_classifier.dart';

/// Derived features computed once per sequence and shared across rules — the
/// Dart mirror of `src/boxing_coach/analysis/features.py`.

/// One detected punch by one hand.
class PunchEvent {
  const PunchEvent({
    required this.side,
    required this.startIndex,
    required this.peakIndex,
    required this.endIndex,
    required this.peakReach,
    this.punchType = PunchType.unknown,
  });

  final Side side;
  final int startIndex; // frame where reach began rising past baseline
  final int peakIndex; // frame of maximum extension
  final int endIndex; // frame where the hand had retracted back to baseline
  final double peakReach; // normalised wrist->shoulder distance at peak
  final PunchType punchType;

  double peakTimestampMs(PoseSequence sequence) =>
      sequence.frames[peakIndex].timestampMs;
}

/// Tuning for [PunchDetector]. Defaults mirror the Python `PunchDetectorConfig`.
class PunchDetectorConfig {
  const PunchDetectorConfig({
    this.prominence = 0.45,
    this.retractionRatio = 0.35,
    this.minDurationMs = 60.0,
    this.baselinePercentile = 25.0,
    this.minTravel = 0.3,
  });

  /// How far above baseline reach must rise (torso-lengths) to count.
  final double prominence;

  /// Reach must fall back to within this of baseline to close the event.
  final double retractionRatio;

  /// Ignore blips shorter than this (milliseconds).
  final double minDurationMs;

  /// Percentile of reach treated as the retracted/guard baseline.
  final double baselinePercentile;

  /// A reach bump we can't classify (unknown) whose wrist travelled less than
  /// this (torso-lengths) is a held-out / range-finding hand, not a stroke.
  final double minTravel;
}

/// Detects punch events from normalised wrist-reach signals — a prominent local
/// maximum in reach relative to the boxer's own idle baseline, not a hard pixel
/// threshold.
class PunchDetector {
  PunchDetector({
    PunchDetectorConfig? config,
    PunchClassifierConfig? classifierConfig,
  }) : _config = config ?? const PunchDetectorConfig(),
       _classifierConfig = classifierConfig ?? const PunchClassifierConfig();

  final PunchDetectorConfig _config;
  final PunchClassifierConfig _classifierConfig;

  List<PunchEvent> detect(PoseSequence sequence, double bodyScale) {
    final events = <PunchEvent>[
      for (final side in Side.values)
        ..._detectSide(sequence, side, bodyScale),
    ]..sort((a, b) => a.peakIndex.compareTo(b.peakIndex));
    return events;
  }

  /// Normalised wrist->shoulder distance per frame (NaN where missing).
  List<double> reachSignal(PoseSequence sequence, Side side, double bodyScale) {
    final out = List<double>.filled(sequence.length, double.nan);
    for (var i = 0; i < sequence.frames.length; i++) {
      final frame = sequence.frames[i];
      final wrist = geo.framePoint(frame, side.wrist);
      final shoulder = geo.framePoint(frame, side.shoulder);
      if (wrist.any((v) => v.isNaN) || shoulder.any((v) => v.isNaN)) continue;
      out[i] = geo.distance(wrist, shoulder) / bodyScale;
    }
    return out;
  }

  List<PunchEvent> _detectSide(
    PoseSequence sequence,
    Side side,
    double bodyScale,
  ) {
    final reach = reachSignal(sequence, side, bodyScale);
    if (reach.every((v) => v.isNaN)) return <PunchEvent>[];

    // Baseline = the boxer's retracted/guard reach, a low percentile. The
    // median breaks down when a hand lingers extended or dropped.
    final baseline = geo.nanPercentile(reach, _config.baselinePercentile);
    final riseLevel = baseline + _config.prominence;
    final closeLevel =
        baseline + _config.prominence * _config.retractionRatio;

    final events = <PunchEvent>[];
    final n = reach.length;
    var i = 0;
    while (i < n) {
      if (reach[i].isNaN || reach[i] < riseLevel) {
        i++;
        continue;
      }

      // Entered a punch: walk back to where it left baseline...
      var start = i;
      while (start > 0 &&
          (reach[start - 1].isNaN || reach[start - 1] > closeLevel)) {
        start--;
      }
      // ...forward to where it returns to baseline.
      var end = i;
      while (end < n - 1 &&
          (reach[end + 1].isNaN || reach[end + 1] > closeLevel)) {
        end++;
      }

      final window = reach.sublist(start, end + 1);
      final peak = start + geo.nanArgmax(window);

      final duration = sequence.frames[end].timestampMs -
          sequence.frames[start].timestampMs;
      if (duration >= _config.minDurationMs) {
        final punchType = classifyPunch(
          sequence,
          side,
          start,
          peak,
          reach[peak],
          bodyScale,
          config: _classifierConfig,
        );
        // Drop phantom detections: a bump we can't classify AND whose wrist
        // barely moved is a held-out hand or a boundary frame, not a stroke.
        final travel = _wristTravel(sequence, side, start, peak, bodyScale);
        final phantom =
            punchType == PunchType.unknown && travel < _config.minTravel;
        if (!phantom) {
          events.add(
            PunchEvent(
              side: side,
              startIndex: start,
              peakIndex: peak,
              endIndex: end,
              peakReach: reach[peak],
              punchType: punchType,
            ),
          );
        }
      }
      i = end + 1;
    }
    return events;
  }

  /// Total wrist path length over the out-stroke (start->peak), torso-lengths.
  /// The actual travelled path, so an arcing punch still reads as travel while a
  /// near-motionless bump reads as ~0.
  static double _wristTravel(
    PoseSequence sequence,
    Side side,
    int startIndex,
    int peakIndex,
    double bodyScale,
  ) {
    var total = 0.0;
    List<double>? prev;
    for (var j = startIndex; j <= peakIndex; j++) {
      final w = geo.framePoint(sequence.frames[j], side.wrist);
      if (prev != null && !w.any((v) => v.isNaN) && !prev.any((v) => v.isNaN)) {
        total += geo.distance(w, prev) / bodyScale;
      }
      prev = w;
    }
    return total;
  }
}

/// Per-frame speed of the stance centre (ankle midpoint), torso-lengths/sec —
/// the in-and-out signal a rule reads to tell "planted" from "stepping in/out".
/// Ported from `round_profile.stance_speed_series`.
///
/// Index-aligned to `sequence.frames`: element i is the speed of the step *into*
/// frame i; frame 0 is 0.0, and a gap (a missing ankle either side) yields NaN,
/// so callers treat "unknown" as not-moving rather than fabricating motion.
List<double> stanceSpeedSeries(PoseSequence sequence, double scale) {
  final frames = sequence.frames;
  final n = frames.length;
  final speeds = List<double>.filled(n, 0.0);
  if (n < 2 || scale <= 0) return speeds;
  for (var i = 1; i < n; i++) {
    final a = geo.ankleCenter(frames[i - 1]);
    final b = geo.ankleCenter(frames[i]);
    final step = <double>[b[0] - a[0], b[1] - a[1]];
    final dt = (frames[i].timestampMs - frames[i - 1].timestampMs) / 1000.0;
    if (step.any((v) => v.isNaN) || dt <= 0) {
      speeds[i] = double.nan;
      continue;
    }
    final stepNorm = geo.distance(a, b);
    speeds[i] = (stepNorm / scale) / dt;
  }
  return speeds;
}

/// Median torso length across frames — the person-and-camera-invariant length
/// unit every rule divides by, so thresholds are expressed in "torso-lengths"
/// and hold across people and camera distances rather than pixels.
///
/// Throws if the sequence never yields a usable torso measurement, since every
/// rule's thresholds depend on it.
double computeBodyScale(PoseSequence sequence) {
  final lengths = <double>[
    for (final frame in sequence.frames) geo.torsoLength(frame),
  ];
  final scale = geo.nanMedian(lengths);
  if (!scale.isFinite || scale <= 0) {
    throw StateError(
      'could not establish body scale — no frame had both shoulders and hips '
      'visible',
    );
  }
  return scale;
}
