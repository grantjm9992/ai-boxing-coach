import 'dart:convert';

import '../../analysis/schools.dart';
import '../../analysis/style_profiles.dart';
import '../../services/ai/video_vision_model.dart';
import '../analysis/fighter_analysis.dart';
import '../analysis/interaction.dart';
import '../analysis/sparring_analyzer.dart';
import '../model/fighter.dart';
import '../model/sparring_session.dart';
import '../pose/multi_pose.dart';
import '../tracking/appearance.dart';
import '../tracking/fighter_tracker.dart';

/// Builds the AI coach's request for one sparring round: the whole video, who
/// is who (described *and* tracked — a box per fighter twice a second, so the
/// model can't mix them up through crossings), both fighters' measurements and
/// the interaction metrics, and the windows the tracker couldn't resolve.
/// Pure, so it's tested without a model.
class SparringPrompt {
  const SparringPrompt._();

  /// Box track sampling interval.
  static const double boxStepMs = 500;

  static VideoVisionRequest request({
    required SparringSession session,
    required int roundNumber,
    required TrackedRound tracked,
    required SparringRoundAnalysis analysis,
    required String videoPath,
    Map<FighterLabel, FighterSetup> setups = const <FighterLabel, FighterSetup>{},
    double fps = kFullReviewFps,
  }) {
    final seconds = tracked.durationMs / 1000;
    final buffer = StringBuffer()
      ..writeln(
        'Sparring round $roundNumber of ${session.settings.rounds}, '
        '${seconds.toStringAsFixed(0)} s, filmed side-on from ringside. The '
        'video is sampled at ${fps.toStringAsFixed(0)} frames per second; '
        'timestamps are seconds from the start of the video.',
      )
      ..writeln()
      ..writeln('The two fighters:');
    for (final label in FighterLabel.values) {
      buffer.writeln('- ${describeFighter(session, tracked, analysis, label, setups[label])}');
    }
    buffer
      ..writeln()
      ..writeln(
        'Where each fighter is, every 0.5 s, as a box in normalised image '
        'coordinates (x0,y0,x1,y1; 0,0 is the top-left). "-" means the '
        "on-device tracker couldn't place them then. Use these boxes to keep "
        'track of who is who, especially after they cross or clinch.',
      );
    for (final label in FighterLabel.values) {
      buffer.writeln('Fighter ${label.letter}: ${boxTrack(tracked, label)}');
    }
    final windows = unresolvedWindows(tracked);
    if (windows.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          'Windows the tracker could not resolve (clinches, crossings): '
          '${windows.join(', ')}. Be careful about who is who there.',
        );
    }
    buffer
      ..writeln()
      ..writeln('On-device measurements for both fighters (JSON):')
      ..writeln(const JsonEncoder.withIndent('  ').convert(measurements(session, analysis)))
      ..writeln()
      ..writeln(
        'Watch the whole round. Coach both fighters fully, then the exchanges '
        'and defence. Return only the JSON report.',
      );

    return VideoVisionRequest(
      systemPrompt: systemPrompt,
      userPrompt: buffer.toString().trim(),
      videoPath: videoPath,
      fps: fps,
      responseSchema: responseSchema,
      // Two fighters' findings, exchanges and defence, after a thinking model
      // has reasoned over a long video.
      maxTokens: 12000,
      temperature: 0.2,
    );
  }

  /// "Fighter A — You: orthodox, high guard. Wearing …; kit colours seen: …;
  /// starts on the left."
  static String describeFighter(
    SparringSession session,
    TrackedRound tracked,
    SparringRoundAnalysis analysis,
    FighterLabel label,
    FighterSetup? setup,
  ) {
    final parts = <String>[];
    final name = session.identified
        ? (label == FighterLabel.a ? 'the user (the person being coached)' : session.nameOf(label))
        : null;
    final stance = analysis.fighter(label).stance;
    parts.add('${stance.name}${analysis.fighter(label).stanceInferred ? ' (inferred)' : ''}');
    if (setup != null) {
      parts.add(profileForStyle(setup.style).label.toLowerCase());
      final school = setup.school;
      if (school != null) parts.add('${schoolProfileFor(school).label} school');
    }
    final kit = session.identified
        ? (label == FighterLabel.a ? session.youKit : session.partnerKit)
        : null;
    final template = tracked.templates[label];
    final seen = <String>[];
    if (template != null) {
      final top = dominantColourName(template.appearance, shorts: false);
      final shorts = dominantColourName(template.appearance, shorts: true);
      if (top != null) seen.add('top $top');
      if (shorts != null) seen.add('shorts $shorts');
    }
    final side = _startSide(tracked, label);
    return 'Fighter ${label.letter}${name == null ? '' : ' — $name'}: ${parts.join(', ')}.'
        '${kit != null && kit.trim().isNotEmpty ? ' Wearing: ${kit.trim()}.' : ''}'
        '${seen.isEmpty ? '' : ' Kit colours the camera saw: ${seen.join(', ')}.'}'
        '${side == null ? '' : ' Starts on the $side.'}';
  }

  static String? _startSide(TrackedRound tracked, FighterLabel label) {
    final me = tracked.fighters[label]!;
    final them = tracked.fighters[label.other]!;
    for (var p = 0; p < tracked.frameCount; p++) {
      final a = PoseCandidate(keypoints: me.frames[p].keypoints).hip;
      final b = PoseCandidate(keypoints: them.frames[p].keypoints).hip;
      if (a != null && b != null) return a[0] < b[0] ? 'left' : 'right';
    }
    return null;
  }

  /// "0.0: 0.21,0.30,0.38,0.92; 0.5: …" with "-" where unresolved.
  static String boxTrack(TrackedRound tracked, FighterLabel label) {
    final seq = tracked.fighters[label]!;
    if (tracked.frameCount == 0) return '-';
    final out = <String>[];
    final start = tracked.timestampsMs.first;
    for (var t = start; t <= tracked.timestampsMs.last + 1; t += boxStepMs) {
      final frame = seq.frameAtTimestamp(t);
      final secs = ((t - start) / 1000).toStringAsFixed(1);
      if (frame == null || frame.keypoints.isEmpty) {
        out.add('$secs: -');
        continue;
      }
      final box = PoseCandidate(keypoints: frame.keypoints).box;
      if (box.area == 0) {
        out.add('$secs: -');
        continue;
      }
      out.add('$secs: ${box.toList().map((v) => v.toStringAsFixed(2)).join(',')}');
    }
    return out.join('; ');
  }

  /// Time windows (seconds) where either fighter wasn't resolved, merged.
  static List<String> unresolvedWindows(TrackedRound tracked) {
    final flagged = <bool>[
      for (var p = 0; p < tracked.frameCount; p++)
        !tracked.isResolved(FighterLabel.a, p) || !tracked.isResolved(FighterLabel.b, p),
    ];
    final minFrames = (tracked.fps * 0.5).round();
    final start = tracked.timestampsMs.isEmpty ? 0.0 : tracked.timestampsMs.first;
    return <String>[
      for (final r in FrameRange.fromFlags(flagged))
        if (r.length >= minFrames)
          '${((tracked.timestampsMs[r.start] - start) / 1000).toStringAsFixed(1)}–'
              '${((tracked.timestampsMs[r.end - 1] - start) / 1000).toStringAsFixed(1)} s',
    ];
  }

  /// The JSON the model reasons over.
  static Map<String, Object?> measurements(
    SparringSession session,
    SparringRoundAnalysis analysis,
  ) {
    double secs(double ms) => (ms / 100).round() / 10;
    Map<String, Object?> fighter(FighterLabel label) {
      final f = analysis.fighter(label);
      final i = analysis.interaction.fighters[label];
      return <String, Object?>{
        'stance': f.stance.name,
        'seconds_tracked': f.analysedSeconds.round(),
        'punches_thrown': f.punchCount,
        'punches_per_minute': (f.punchesPerMinute * 10).round() / 10,
        'punch_mix': f.punchMix,
        'rule_flags': <Object?>[
          for (final o in f.observations)
            if (o.severity.isFault)
              <String, Object?>{
                'code': o.code,
                'at': o.timestampMs == null ? null : secs(o.timestampMs!),
                'note': o.coachingText,
              },
        ],
        if (i != null) ...<String, Object?>{
          'counters': i.counters,
          'hands_up_while_punched_at': i.guardUnderFire == null
              ? null
              : '${(i.guardUnderFire! * 100).round()}%',
          'fist_reached_head_2d': i.landedHeadCandidates,
          'fist_reached_body_2d': i.landedBodyCandidates,
          'response_to_punches': i.defence.toJson(),
          'exchanges_started': i.exchangesStarted,
        },
      };
    }

    final interaction = analysis.interaction;
    return <String, Object?>{
      'fighter_a': fighter(FighterLabel.a),
      'fighter_b': fighter(FighterLabel.b),
      'range_seconds': <String, int>{
        for (final band in DistanceBand.values)
          band.name: (interaction.bandSeconds[band] ?? 0).round(),
      },
      'exchanges': <Object?>[
        for (final e in interaction.exchanges)
          <String, Object?>{
            'start': secs(e.startMs),
            'end': secs(e.endMs),
            'started_by': e.startedBy.letter,
            'punches': <String, int>{
              for (final p in e.punches.entries) p.key.letter: p.value,
            },
          },
      ],
      'notes': 'fist_reached_* are 2D overlaps, not confirmed contact. '
          'response_to_punches is in-plane only (side-on, slips are mostly depth).',
    };
  }

  static const String systemPrompt =
      'You are an elite boxing coach reviewing one round of sparring between '
      'two fighters, filmed side-on from ringside. You also get measurements '
      'from an on-device pose tracker for both fighters. Treat them as leads, '
      'not verdicts: confirm or reject them against the video and find what '
      'they missed. The tracker cannot see depth: it cannot tell a landed punch '
      'from one that fell short, and it barely sees slips.\n'
      '\n'
      'Identity matters above everything: the fighters are labelled A and B, '
      'described by kit and position, with a box track for each. Never '
      'attribute a punch, a fault or a strength to the wrong fighter. If you '
      'cannot tell who did something, leave it out.\n'
      '\n'
      'For EACH fighter, coach fully, covering: guard (hands home, the other '
      'hand dropping while punching, elbows), chin, punch mechanics and '
      'rotation, balance and weight after punching, footwork and ring position '
      '(cut off, backed onto the ropes, circling), head movement and defence, '
      'output and rhythm, counter-punching, and what they do after their own '
      'combinations. Then the exchanges: who starts them, who finishes, what '
      'works. Then defence: sample attacks and how they were defended.\n'
      '\n'
      'Per fighter, report every distinct fault you can clearly see, worst '
      'first, up to 7, never padded. Each finding needs 1–3 timestamps where '
      'it is clearest and a calibrated confidence: 0.9 or more seen clearly '
      'and repeatedly, about 0.7 seen clearly once, below 0.5 unsure. Use a '
      'code from this list, or "OTHER": GUARD_001 lead hand low; GUARD_002 '
      'rear hand low; GUARD_003 lead drops during rear punch; GUARD_004 rear '
      'drops during lead punch; GUARD_005 slow guard recovery; GUARD_006 both '
      'hands low; GUARD_007 chin exposed; ROT_001 insufficient rotation; '
      'ROT_005 rotation not recovered; BAL_001 off balance after punch; '
      'BAL_002 off balance after combination; BAL_003 weight too far forward; '
      'FOOT_001 feet crossing; FOOT_004 feet too square; FOOT_009 flat-footed; '
      'LEAN_001 leaning forward; POS_001 head too far forward; REC_002 hand '
      'not returned; REC_003 overextended; HEAD_001 head static on the centre '
      'line; TENSE_001 tense. "landed_estimate" is your estimate of clean '
      'punches that fighter landed; omit it if you cannot judge.\n'
      '\n'
      'Write each fighter\'s coaching to that fighter, in the second person, '
      'in a direct coach\'s voice. "summary" for each fighter is 2–4 '
      'sentences; the top-level "summary" is 2–4 sentences on the round as a '
      'whole. "observation" is one sentence on what you saw; "correction" one '
      'short cue. Respond with JSON only.';

  static const Map<String, Object?> _issueSchema = <String, Object?>{
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
      'suggested_drill': <String, Object?>{'type': 'STRING'},
    },
    'required': <String>['code', 'severity', 'confidence', 'timestamps', 'observation', 'correction'],
  };

  static const Map<String, Object?> _fighterSchema = <String, Object?>{
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
        'maxItems': kSparringMaxFindings,
        'items': _issueSchema,
      },
      'landed_estimate': <String, Object?>{'type': 'INTEGER'},
      'patterns': <String, Object?>{
        'type': 'ARRAY',
        'items': <String, Object?>{'type': 'STRING'},
        'maxItems': 4,
      },
    },
    'required': <String>['summary', 'strengths', 'priority_issues'],
  };

  /// Gemini `responseSchema` for the sparring review.
  static const Map<String, Object?> responseSchema = <String, Object?>{
    'type': 'OBJECT',
    'properties': <String, Object?>{
      'summary': <String, Object?>{'type': 'STRING'},
      'fighter_a': _fighterSchema,
      'fighter_b': _fighterSchema,
      'exchanges': <String, Object?>{
        'type': 'ARRAY',
        'maxItems': 12,
        'items': <String, Object?>{
          'type': 'OBJECT',
          'properties': <String, Object?>{
            'start': <String, Object?>{'type': 'NUMBER'},
            'end': <String, Object?>{'type': 'NUMBER'},
            'started_by': <String, Object?>{
              'type': 'STRING',
              'enum': <String>['A', 'B'],
            },
            'summary': <String, Object?>{'type': 'STRING'},
          },
          'required': <String>['start', 'summary'],
        },
      },
      'defence': <String, Object?>{
        'type': 'ARRAY',
        'maxItems': 12,
        'items': <String, Object?>{
          'type': 'OBJECT',
          'properties': <String, Object?>{
            'time': <String, Object?>{'type': 'NUMBER'},
            'defender': <String, Object?>{
              'type': 'STRING',
              'enum': <String>['A', 'B'],
            },
            'response': <String, Object?>{'type': 'STRING'},
            'verdict': <String, Object?>{'type': 'STRING'},
          },
          'required': <String>['time', 'defender', 'response', 'verdict'],
        },
      },
    },
    'required': <String>['summary', 'fighter_a', 'fighter_b'],
  };
}
