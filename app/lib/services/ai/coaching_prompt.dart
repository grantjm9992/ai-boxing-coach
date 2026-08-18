import 'dart:math' as math;

import '../../analysis/drill.dart';
import '../../analysis/round_analysis.dart';
import 'vision_model.dart';

/// Builds the vision-model prompts and chooses which frames to send. Pure, so
/// the prompt shape and frame selection are unit-tested without a model.
class CoachingPrompt {
  const CoachingPrompt._();

  static const String _system =
      'You are a sharp, experienced boxing coach reviewing a shadow-boxing '
      'round. Speak in a short, direct coach\'s voice — no preamble, no '
      'hedging, no numbered essays. Confirm what the fighter is doing well and '
      'give at most two concrete corrections they can act on next round.';

  /// The timestamps (ms) worth sending in keyframe mode: where the rules flagged
  /// something. Deduped, sorted, capped at [max].
  static List<double> keyframeTimestamps(RoundAnalysis analysis, {int max = 6}) {
    final times = <double>{
      for (final c in analysis.correctionPriorities)
        if (c.exampleTimestampMs != null) c.exampleTimestampMs!,
      for (final f in analysis.flaggedMoments) f.timestampMs,
    }.toList()..sort();
    return times.length <= max ? times : times.sublist(0, max);
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
    List<VisionImage> images,
  ) {
    final buffer = StringBuffer()
      ..writeln(_context(drill))
      ..writeln('Our on-device rules analysed the round and found:')
      ..writeln(analysis.overallSummary);
    if (analysis.correctionPriorities.isNotEmpty) {
      buffer.writeln('\nFlagged points:');
      for (final c in analysis.correctionPriorities) {
        final at = c.exampleTimestampMs == null
            ? ''
            : ' (~${(c.exampleTimestampMs! / 1000).toStringAsFixed(1)}s)';
        buffer.writeln('- ${c.description}$at');
      }
    }
    buffer.writeln(
      '\nThe attached frames are those flagged moments, in order. Look at them '
      'and give the fighter your read: confirm or correct what the rules saw, '
      'in your own words.',
    );
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
