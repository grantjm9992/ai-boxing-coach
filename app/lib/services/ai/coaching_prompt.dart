import 'dart:convert';
import 'dart:math' as math;

import '../../analysis/ai_review.dart';
import '../../analysis/checkpoints.dart';
import '../../analysis/drill.dart';
import '../../analysis/round_analysis.dart';
import '../../analysis/schools.dart';
import '../../analysis/style_profiles.dart';
import 'video_vision_model.dart';
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

  /// The round's moments — each correction's example instant, then any bare
  /// flagged moment at an instant no correction covers — with their labels.
  /// The most important [max] are kept (corrections in priority order before
  /// bare flags), then returned in time order for display. Distinct corrections
  /// that share an instant are both kept; only an identical label at the same
  /// instant is a duplicate.
  static List<KeyframeMoment> keyframeMoments(
    RoundAnalysis analysis, {
    int max = kMaxFindings,
  }) {
    final moments = <KeyframeMoment>[];
    final correctionTimes = <double>{};
    bool isDuplicate(double t, String? label) =>
        moments.any((m) => m.timestampMs == t && m.label == label);

    final corrections = List<Correction>.of(analysis.correctionPriorities)
      ..sort((a, b) => a.priority.compareTo(b.priority));
    for (final c in corrections) {
      final t = c.exampleTimestampMs;
      if (t == null || isDuplicate(t, c.description)) continue;
      correctionTimes.add(t);
      moments.add(KeyframeMoment(timestampMs: t, label: c.description));
    }
    // A flagged moment carries its own specific reason (the observation's coach
    // text) — use it as the label so the review/history strips read e.g. "Rear
    // hand drifts down", not a bare "Flagged moment". A correction at the same
    // instant already covers it.
    for (final f in analysis.flaggedMoments) {
      if (correctionTimes.contains(f.timestampMs)) continue;
      final reason = f.reason.trim();
      final label = reason.isEmpty ? null : reason;
      if (isDuplicate(f.timestampMs, label)) continue;
      moments.add(KeyframeMoment(timestampMs: f.timestampMs, label: label));
    }
    final kept = moments.length <= max ? moments : moments.sublist(0, max);
    return kept..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
  }

  /// The single representative timestamp (ms) per flagged moment. Deduped,
  /// sorted, capped at [max]. This is the one-frame-per-error set used for the
  /// stored history keyframes.
  static List<double> keyframeTimestamps(
    RoundAnalysis analysis, {
    int max = kMaxFindings,
  }) =>
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
    int maxMoments = kMaxFindings,
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

  /// Evenly spaced timestamps (ms) across a round, at [fps], capped at [max]
  /// so cost stays bounded. Context frames for the advanced structured path.
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
    final brief = drillBrief(drill);
    final buffer = StringBuffer()..writeln(_context(drill));
    if (brief.isNotEmpty) {
      buffer.writeln(
        '$brief\nJudge the drill against these checkpoints first — they '
        'matter more than anything else in the round.\n',
      );
    }
    buffer
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

  /// Full AI review: the whole round's video, sampled by the provider at
  /// [fps], with the on-device pose measurements (the same payload as the
  /// structured path: punches, combinations, metrics, detected and
  /// low-confidence issues), the fighter's style and school, and the rules'
  /// flagged points as candidates to confirm or reject. The model returns a
  /// JSON report (enforced by [fullVideoResponseSchema]) with up to
  /// [kMaxFindings] timestamped, confidence-scored findings; parse it with
  /// `AiCoachReport.tryParse` and fold it in with `AiReview.apply`.
  static VideoVisionRequest fullVideoRequest(
    RoundAnalysis analysis,
    DrillContext drill, {
    required String videoPath,
    double fps = kFullReviewFps,
    double? durationSeconds,
  }) {
    final input = structuredInput(
      analysis,
      drill,
      durationSeconds: durationSeconds,
    );
    final moments = keyframeMoments(analysis);
    final length = durationSeconds == null
        ? ''
        : ' (${durationSeconds.toStringAsFixed(0)} s)';
    final brief = drillBrief(drill);
    final buffer = StringBuffer()
      ..writeln(_context(drill))
      ..writeln(_styleAndSchool(drill));
    if (brief.isNotEmpty) buffer.writeln('\n$brief');
    buffer
      ..writeln(
        '\nThe attached video is the whole round$length, sampled at '
        '${_fps(fps)} frames per second. Timestamps are seconds from the start '
        'of the video.',
      )
      ..writeln('\nOn-device pose analysis of the round (JSON):')
      ..writeln(const JsonEncoder.withIndent('  ').convert(input));
    if (moments.isNotEmpty) {
      buffer.writeln('\nPoints the pose rules flagged — confirm or reject each:');
      for (var i = 0; i < moments.length; i++) {
        final m = moments[i];
        final at = (m.timestampMs / 1000).toStringAsFixed(1);
        buffer.writeln('${i + 1}. ${m.label ?? 'flagged moment'} (at ${at}s)');
      }
    }
    buffer.writeln(
      '\nWatch the whole round, work through every area of the checklist, and '
      'return only the JSON report.',
    );
    return VideoVisionRequest(
      systemPrompt: _fullVideoSystem,
      userPrompt: buffer.toString().trim(),
      videoPath: videoPath,
      fps: fps,
      responseSchema: fullVideoResponseSchema,
      // A thinking model reasons over a long video before it writes; leave room
      // for both and for up to seven findings.
      maxTokens: 8192,
      temperature: 0.2,
    );
  }

  static const String _fullVideoSystem =
      'You are an elite boxing coach reviewing one full round on video. You also '
      'get measurements from an on-device pose engine. That engine is rigid: it '
      'can mistake a deliberate style choice or a defensive move (a slip, a '
      'roll, a low lead hand in a shell) for a fault, and it cannot see some '
      'things at all (chin position, tension, telegraphing). Treat its '
      'measurements and flags as leads, not verdicts: confirm or reject each '
      'against the video, and find what it missed.\n'
      '\n'
      'Work through every area, whether or not the engine flagged it:\n'
      '- Guard: lead and rear hand height, elbows in, hands returning to the '
      'face, the other hand dropping while one punches.\n'
      '- Chin: tucked behind the lead shoulder, not lifting on punches or '
      'movement.\n'
      '- Punch mechanics: full extension without locking out or over-reaching, '
      'snapping back on the same line, no winding up or telegraphing.\n'
      '- Rotation: hips and shoulders turning through straights and hooks, the '
      'rear heel pivoting, rotation recovered after the punch.\n'
      '- Balance and weight: centred after punches and combinations, no '
      'falling in, no corrective steps.\n'
      '- Stance and footwork: width, not squaring up, feet never crossing, '
      'moving on the balls of the feet, neither foot lagging.\n'
      '- Posture: lean, head past the front knee, knee bend, staying upright '
      'enough to see.\n'
      '- Head movement: getting off the centre line, especially after '
      'punching.\n'
      '- Relaxation: shoulders and arms loose between punches.\n'
      '- Combinations and rhythm: flow between punches, balance through the '
      'combination.\n'
      '\n'
      'When the input has a "drill_target", the round is a drill of that '
      'combination or punch, and its checkpoints are what the drill is for. '
      'Grade every checkpoint on every rep you can see — the on-device results '
      'are a lead, and checkpoints it could not measure are yours to judge. '
      'Checkpoint failures carry the most weight: report each one you can see '
      'as a finding with its checkpoint id in "checkpoint", rank them above '
      'general faults of the same severity, and open the summary with how the '
      'drill\'s checkpoints went. Leave "checkpoint" empty for general '
      'findings.\n'
      '\n'
      'Judge against the fighter\'s chosen guard style and school: what is '
      'correct for a Philly shell or a peek-a-boo is a fault in a textbook high '
      'guard, and the reverse.\n'
      '\n'
      'Report every distinct fault you can clearly see in the video, worst '
      'first, up to $kMaxFindings. Do not pad the list: fewer findings is the '
      'right answer for a cleaner round, and a fault you cannot point to in '
      'the video must not be reported. For each finding give 1–3 timestamps '
      '(seconds from the start of the video) where it is clearest, and a '
      'calibrated confidence: 0.9 or more seen clearly and repeatedly, about '
      '0.7 seen clearly once, below 0.5 unsure. Use a code from this list, or '
      '"OTHER" if none fits:\n'
      '$_taxonomy\n'
      '\n'
      'Write to the fighter in the second person, in a direct coach\'s voice. '
      '"summary" is your spoken read of the round, 3–6 sentences: what is '
      'working, then the one or two things that matter most. "strengths" are '
      'up to 4 short lines on what is genuinely good. For each finding, '
      '"observation" is one sentence on what you saw and "correction" is one '
      'short, actionable cue. Respond with JSON only.';

  /// The canonical fault codes (annotations/taxonomy/codes.json) the model may
  /// use for findings, with their meaning.
  static const String _taxonomy =
      'GUARD_001 lead hand low; GUARD_002 rear hand low; GUARD_003 lead drops '
      'during rear punch; GUARD_004 rear drops during lead punch; GUARD_005 '
      'slow guard recovery after punch; GUARD_006 both hands low; GUARD_007 '
      'chin exposed / not tucked; GUARD_008 elbows flared out; ROT_001 '
      'insufficient rotation; ROT_002 '
      'over-rotation; ROT_003 rotation too early; ROT_004 rotation too late; '
      'ROT_005 rotation not recovered; BAL_001 off balance after punch; '
      'BAL_002 off balance after combination; BAL_003 weight too far forward; '
      'BAL_004 weight too far back; BAL_005 corrective step needed; FOOT_001 '
      'feet crossing; FOOT_002 stance too narrow; FOOT_003 stance too wide; '
      'FOOT_004 feet too square; FOOT_005 rear foot lagging; FOOT_006 lead '
      'foot lagging; FOOT_007 stance not recovered; FOOT_008 balance lost '
      'after step; FOOT_009 flat-footed / not moving; LEAN_001 leaning '
      'forward; LEAN_002 leaning back; LEAN_003 leaning left; LEAN_004 '
      'leaning right; POS_001 head too far forward; POS_002 head over front '
      'knee; POS_003 too upright; POS_004 position not recovered; POS_005 off '
      'centre after punch; POS_006 insufficient knee bend; REC_001 slow '
      'retraction; REC_002 hand not returned; REC_003 overextended; HEAD_001 '
      'head static on the centre line; TENSE_001 upper body tense / rigid; '
      'PUNCH_001 head-level punch landing below shoulder height; PUNCH_002 '
      'hook arm not bent near 90 degrees; PUNCH_003 hook thrown downward, '
      'not level at shoulder height.';

  /// Gemini `responseSchema` for the Full AI review — the §18 report shape,
  /// with findings capped at [kMaxFindings] and each required to carry its
  /// timestamps and confidence.
  static const Map<String, Object?> fullVideoResponseSchema = <String, Object?>{
    'type': 'OBJECT',
    'properties': <String, Object?>{
      'summary': <String, Object?>{'type': 'STRING'},
      'strengths': <String, Object?>{
        'type': 'ARRAY',
        'items': <String, Object?>{'type': 'STRING'},
        'maxItems': 4,
      },
      'priority_issues': <String, Object?>{
        'type': 'ARRAY',
        'maxItems': kMaxFindings,
        'items': <String, Object?>{
          'type': 'OBJECT',
          'properties': <String, Object?>{
            'code': <String, Object?>{'type': 'STRING'},
            'severity': <String, Object?>{
              'type': 'STRING',
              'enum': <String>['HIGH', 'MEDIUM', 'LOW'],
            },
            'confidence': <String, Object?>{'type': 'NUMBER'},
            'timestamps': <String, Object?>{
              'type': 'ARRAY',
              'items': <String, Object?>{'type': 'NUMBER'},
              'minItems': 1,
              'maxItems': 3,
            },
            'observation': <String, Object?>{'type': 'STRING'},
            'correction': <String, Object?>{'type': 'STRING'},
            'why_it_matters': <String, Object?>{'type': 'STRING'},
            'suggested_drill': <String, Object?>{'type': 'STRING'},
            'checkpoint': <String, Object?>{'type': 'STRING'},
          },
          'required': <String>[
            'code',
            'severity',
            'confidence',
            'timestamps',
            'observation',
            'correction',
          ],
        },
      },
      'next_session_focus': <String, Object?>{
        'type': 'ARRAY',
        'items': <String, Object?>{'type': 'STRING'},
        'maxItems': 3,
      },
    },
    'required': <String>['summary', 'strengths', 'priority_issues'],
  };

  /// What the fighter's guard style and school mean, so the model judges
  /// against them rather than against a textbook high guard.
  static String _styleAndSchool(DrillContext drill) {
    final style = profileForStyle(drill.style);
    final buffer = StringBuffer()
      ..write('Guard style — ${style.label}: ${style.summary}');
    final school = drill.school;
    if (school != null) {
      final profile = schoolProfileFor(school);
      buffer.write('\nSchool — ${profile.label}: ${profile.summary}');
    }
    return buffer.toString();
  }

  static String _fps(double fps) =>
      fps == fps.roundToDouble() ? fps.toStringAsFixed(0) : fps.toStringAsFixed(1);

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
      if (drill.targetSequence case final target? when target.isNotEmpty)
        'drill_target': drillTarget(analysis, target),
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

  /// The drill's target and technique checkpoints, with how the on-device
  /// engine graded each — the part of the input the model must weigh first.
  static Map<String, Object?> drillTarget(
    RoundAnalysis analysis,
    List<int> target,
  ) {
    return <String, Object?>{
      'sequence': target,
      'punches': <String>[for (final n in target) Checkpoints.punchLabel(n)],
      'checkpoints': <Object?>[
        for (final dc in Checkpoints.forSequence(target)) dc.toJson(),
      ],
      'on_device_results': <Object?>[
        for (final t in analysis.checkpointTallies)
          <String, Object?>{
            'id': t.checkpoint.id,
            'passed': t.passed,
            'failed': t.failed,
            'not_measurable': t.unmeasured,
          },
      ],
    };
  }

  /// A readable version of the drill's checkpoints for the prompt text, punch
  /// by punch. Empty when the round has no target.
  static String drillBrief(DrillContext drill) {
    final target = drill.targetSequence;
    if (target == null || target.isEmpty) return '';
    final names = <String>[for (final n in target) Checkpoints.punchLabel(n)];
    final buffer = StringBuffer()
      ..writeln(
        'This round is a drill of ${target.join('-')} '
        '(${names.join(', ')}). What it is looking for, punch by punch:',
      );
    String? current;
    for (final dc in Checkpoints.forSequence(target)) {
      if (dc.punchName != current) {
        current = dc.punchName;
        buffer.writeln('$current:');
      }
      buffer.writeln('- [${dc.id}] ${dc.checkpoint.detail}');
    }
    return buffer.toString().trimRight();
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
