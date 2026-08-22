import 'dart:math' as math;

import '../../analysis/drill.dart';
import '../../analysis/round_analysis.dart';
import 'vision_model.dart';

/// A moment the rules flagged, with its label where we have one (a correction's
/// description; null for a bare flagged moment).
class KeyframeMoment {
  const KeyframeMoment({required this.timestampMs, this.label});

  final double timestampMs;
  final String? label;
}

/// A flagged moment plus the timestamps of a short burst of frames around it —
/// the movement into and out of the error, not a single frozen still.
class KeyframeBurst {
  const KeyframeBurst({
    required this.centerMs,
    required this.timestamps,
    this.label,
  });

  final double centerMs;

  /// Ascending, in-bounds; the middle entry is [centerMs] when it fits.
  final List<double> timestamps;
  final String? label;
}

/// Builds the vision-model prompts and chooses which frames to send. Pure, so
/// the prompt shape and frame selection are unit-tested without a model.
class CoachingPrompt {
  const CoachingPrompt._();

  static const String _system =
      'You are a sharp, experienced boxing coach reviewing a shadow-boxing '
      'round. Speak in a short, direct coach\'s voice — no preamble, no '
      'hedging, no numbered essays. Confirm what the fighter is doing well and '
      'give at most two concrete corrections they can act on next round.';

  /// The flagged moments worth sending in keyframe mode — a correction's example
  /// instant, or a bare flagged moment — each with its label where we have one.
  /// Deduped by time (a correction's label wins over a bare flag), sorted, and
  /// capped at [max].
  static List<KeyframeMoment> keyframeMoments(
    RoundAnalysis analysis, {
    int max = 6,
  }) {
    final byTime = <double, String?>{};
    for (final c in analysis.correctionPriorities) {
      final t = c.exampleTimestampMs;
      if (t != null) byTime.putIfAbsent(t, () => c.description);
    }
    for (final f in analysis.flaggedMoments) {
      byTime.putIfAbsent(f.timestampMs, () => null);
    }
    final entries = byTime.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final capped = entries.length <= max ? entries : entries.sublist(0, max);
    return <KeyframeMoment>[
      for (final e in capped) KeyframeMoment(timestampMs: e.key, label: e.value),
    ];
  }

  /// The single representative timestamp (ms) per flagged moment. Deduped,
  /// sorted, capped at [max]. This is the one-frame-per-error set used for the
  /// stored history keyframes.
  static List<double> keyframeTimestamps(RoundAnalysis analysis, {int max = 6}) =>
      <double>[for (final m in keyframeMoments(analysis, max: max)) m.timestampMs];

  /// Keyframe mode as a burst of frames around each flagged moment: the moment
  /// plus [context] frames before and after, [spacingMs] apart, so the model
  /// sees the movement into and out of the error rather than a frozen instant.
  /// Each burst has 2*[context]+1 timestamps, shifted to stay within
  /// [0, durationMs]. Bursts are in time order.
  static List<KeyframeBurst> keyframeBursts(
    RoundAnalysis analysis, {
    required double durationMs,
    int context = 3,
    double spacingMs = 100,
    int maxMoments = 6,
  }) {
    return <KeyframeBurst>[
      for (final m in keyframeMoments(analysis, max: maxMoments))
        KeyframeBurst(
          centerMs: m.timestampMs,
          label: m.label,
          timestamps: _burst(m.timestampMs, context, spacingMs, durationMs),
        ),
    ];
  }

  /// The burst of frame timestamps around a single [centerMs] — the same window
  /// [keyframeBursts] uses, exposed so the review/history layers can show (and
  /// upload) exactly the frames the model saw for a moment.
  static List<double> burstTimestamps(
    double centerMs, {
    required double durationMs,
    int context = 3,
    double spacingMs = 100,
  }) => _burst(centerMs, context, spacingMs, durationMs);

  static List<double> _burst(
    double center,
    int context,
    double spacing,
    double durationMs,
  ) {
    final n = context * 2 + 1;
    final span = (n - 1) * spacing;
    var start = center - context * spacing;
    if (start < 0) start = 0;
    if (durationMs > 0 && start + span > durationMs) {
      start = math.max(0.0, durationMs - span);
    }
    return <double>[for (var i = 0; i < n; i++) start + i * spacing];
  }

  /// Evenly spaced timestamps (ms) across a round for full-frame mode, at [fps],
  /// capped at [max] so cost stays bounded.
  static List<double> sampledTimestamps(
    double durationMs, {
    double fps = 3.0,
    int max = 40,
  }) {
    if (durationMs <= 0 || fps <= 0) return const <double>[];
    final stepMs = 1000.0 / fps;
    final count = math.min((durationMs / stepMs).floor() + 1, max);
    final spacing = count > 1 ? durationMs / (count - 1) : 0.0;
    return <double>[for (var i = 0; i < count; i++) i * spacing];
  }

  static VisionRequest keyframeRequest(
    RoundAnalysis analysis,
    DrillContext drill,
    List<KeyframeBurst> bursts,
    List<VisionImage> images,
  ) {
    final perBurst = bursts.isEmpty ? 0 : bursts.first.timestamps.length;
    final buffer = StringBuffer()
      ..writeln(_context(drill))
      ..writeln('Our on-device rules analysed the round and found:')
      ..writeln(analysis.overallSummary);
    if (bursts.isNotEmpty) {
      buffer.writeln('\nFlagged points, in order:');
      for (var i = 0; i < bursts.length; i++) {
        final b = bursts[i];
        final at = '~${(b.centerMs / 1000).toStringAsFixed(1)}s';
        buffer.writeln('${i + 1}. ${b.label ?? 'flagged moment'} ($at)');
      }
      buffer.writeln(
        '\nThe attached frames are these points in the same order — $perBurst '
        'consecutive frames per point (earliest first; the middle frame is the '
        'flagged instant). Read each group of $perBurst as one short motion '
        'sequence — the wind-up, the flagged instant, the recovery — then give '
        'the fighter your read: confirm or correct what the rules saw, in your '
        'own words.',
      );
    } else {
      buffer.writeln(
        '\nThe attached frames are the flagged moments, in order. Give the '
        'fighter your read: confirm or correct what the rules saw.',
      );
    }
    return VisionRequest(
      systemPrompt: _system,
      userPrompt: buffer.toString().trim(),
      images: images,
    );
  }

  static VisionRequest fullFrameRequest(
    DrillContext drill,
    List<VisionImage> images,
  ) {
    final prompt = StringBuffer()
      ..writeln(_context(drill))
      ..writeln(
        'The attached ${images.length} frames are sampled evenly across one '
        'technical boxing round, in time order. Watch the round through them '
        'and give your coaching: what looked good, and the one or two things to '
        'fix next round.',
      );
    return VisionRequest(
      systemPrompt: _system,
      userPrompt: prompt.toString().trim(),
      images: images,
    );
  }

  static String _context(DrillContext drill) {
    final parts = <String>[
      '${drill.stance.name} stance',
      '${drill.style.value.replaceAll('_', ' ')} guard',
      if (drill.school != null) 'training a ${drill.school!.value} game',
      if (drill.notes.isNotEmpty) 'drill: ${drill.notes}',
    ];
    return 'Fighter: ${parts.join(', ')}.';
  }
}
