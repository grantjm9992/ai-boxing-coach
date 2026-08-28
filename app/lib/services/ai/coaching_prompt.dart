import 'dart:convert';
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

  // ---------------------------------------------------------------------------
  // Advanced structured path (brief §17 input, §18 output).
  // ---------------------------------------------------------------------------

  static const String _structuredSystem =
      'You are an expert boxing coach. You are given structured measurements '
      'from an on-device pose/CV analysis of one boxing round, and optionally '
      'frames from it. Ground every judgement in the measurements provided — do '
      'not invent faults the data does not support. Respond with ONLY a single '
      'JSON object, no prose or markdown, matching exactly this schema:\n'
      '{"summary": string, "strengths": [string], "priority_issues": '
      '[{"code": string, "severity": "HIGH"|"MEDIUM"|"LOW", "confidence": '
      'number, "timestamps": [number], "observation": string, '
      '"why_it_matters": string, "correction": string, "suggested_drill": '
      'string}], "combination_feedback": [{"sequence": [number], '
      '"sequence_match": boolean, "score": number, "comment": string}], '
      '"next_session_focus": [string]}\n'
      'Reuse the codes from detected_issues where they apply. At most three '
      'priority_issues, worst first.';

  /// The structured input payload (brief §17): the CV measurements the model
  /// reasons over. Pure JSON-able map, so it's testable without a model.
  static Map<String, Object?> structuredInput(
    RoundAnalysis analysis,
    DrillContext drill, {
    double? durationSeconds,
  }) {
    Map<String, Object?> issue(Observation o) => <String, Object?>{
      'code': o.code,
      'category': o.category.value,
      'severity': o.severity.value,
      'confidence': o.confidence,
      if (o.timestampMs != null) 'timestamp_s': o.timestampMs! / 1000.0,
      'observation': o.coachingText,
      'metrics': o.metrics,
    };

    return <String, Object?>{
      'session': <String, Object?>{
        'type': analysis.sessionType.value,
        'duration_seconds': ?durationSeconds,
      },
      'fighter': <String, Object?>{
        'stance': drill.stance.name,
        'style': drill.style.value,
        if (drill.school != null) 'school': drill.school!.value,
      },
      'capture_quality': const <String, Object?>{},
      'punches': <String, Object?>{
        'count': analysis.metrics.punchesThrown,
        'mix': analysis.metrics.punchMix,
      },
      'combinations': <Object?>[
        for (final c in analysis.combinations)
          <String, Object?>{
            'sequence': c.sequence,
            'label': c.label,
            'confidence': c.confidence,
          },
      ],
      'combination_execution': <Object?>[
        for (final a in analysis.combinationAnalyses)
          <String, Object?>{
            'sequence': a.combination.sequence,
            'score': a.score,
            'issues': <Object?>[
              for (final i in a.issues)
                <String, Object?>{
                  'code': i.code,
                  'severity': i.severity.value,
                  'confidence': i.confidence,
                },
            ],
          },
      ],
      'metrics': <String, Object?>{
        if (analysis.metrics.guardReturnRate != null)
          'guard_return_rate': analysis.metrics.guardReturnRate,
        ...analysis.metrics.values,
      },
      'detected_issues': <Object?>[
        for (final o in analysis.specificObservations)
          if (o.severity.isFault) issue(o),
      ],
      // Below the report threshold — for the model to weigh, not stated as fact
      // to the user (brief §12).
      'low_confidence_observations': <Object?>[
        for (final o in analysis.lowConfidenceObservations) issue(o),
      ],
    };
  }

  /// The advanced request: structured measurements (+ optional frames) in,
  /// strict JSON out. Parse the response with `AiCoachReport.tryParse`.
  static VisionRequest structuredRequest(
    RoundAnalysis analysis,
    DrillContext drill, {
    List<VisionImage> images = const <VisionImage>[],
    double? durationSeconds,
  }) {
    final input = structuredInput(analysis, drill,
        durationSeconds: durationSeconds);
    final buffer = StringBuffer()
      ..writeln(_context(drill))
      ..writeln('On-device analysis of the round (JSON):')
      ..writeln(const JsonEncoder.withIndent('  ').convert(input));
    if (images.isNotEmpty) {
      buffer.writeln(
        '\nThe attached ${images.length} frames are sampled across the round '
        'in time order, for context.',
      );
    }
    buffer.writeln('\nReturn only the JSON report.');
    return VisionRequest(
      systemPrompt: _structuredSystem,
      userPrompt: buffer.toString().trim(),
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
