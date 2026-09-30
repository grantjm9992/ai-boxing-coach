import 'dart:typed_data';

import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/analysis/school.dart';
import 'package:boxing_coach/services/ai/coaching_prompt.dart';
import 'package:boxing_coach/services/ai/video_vision_model.dart';
import 'package:boxing_coach/services/ai/vision_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RoundAnalysis analysis() => RoundAnalysis(
    overallSummary: 'Main thing to fix: guard.',
    correctionPriorities: const <Correction>[
      Correction(
        priority: 1,
        category: SkillCategory.defence,
        description: 'Hand drops.',
        exampleTimestampMs: 900,
      ),
      Correction(
        priority: 2,
        category: SkillCategory.footwork,
        description: 'Flat-footed.',
        exampleTimestampMs: 300,
      ),
    ],
    flaggedMoments: const <FlaggedMoment>[
      FlaggedMoment(timestampMs: 900, reason: 'drop', severity: Severity.moderate),
    ],
  );

  test('keyframeTimestamps are the flagged moments, deduped and sorted', () {
    final t = CoachingPrompt.keyframeTimestamps(analysis());
    // 300 and 900 (900 appears in both a correction and a flag → deduped).
    expect(t, <double>[300, 900]);
  });

  group('keyframeBursts', () {
    test('one burst per flagged moment, 7 frames, centered and ascending', () {
      final bursts = CoachingPrompt.keyframeBursts(analysis(), durationMs: 10000);
      expect(bursts, hasLength(2)); // 300 and 900
      for (final b in bursts) {
        expect(b.timestamps, hasLength(7)); // main + 3 before + 3 after
        expect(b.timestamps[3], b.centerMs); // middle is the flagged instant
        for (var i = 1; i < b.timestamps.length; i++) {
          expect(b.timestamps[i], greaterThan(b.timestamps[i - 1]));
        }
      }
    });

    test('shifts the window so it never goes negative', () {
      final bursts = CoachingPrompt.keyframeBursts(analysis(), durationMs: 10000);
      // center 300, 3×100ms before → clamped start at 0.
      expect(bursts.first.timestamps.first, 0);
    });

    test('a bare flagged moment is labelled with its reason', () {
      // A flag with no correction at its instant must carry its own reason
      // (not fall through to a generic "Flagged moment").
      final a = RoundAnalysis(
        overallSummary: 's',
        flaggedMoments: const <FlaggedMoment>[
          FlaggedMoment(
            timestampMs: 500,
            reason: 'Rear hand drifts down',
            severity: Severity.moderate,
          ),
        ],
      );
      final bursts = CoachingPrompt.keyframeBursts(a, durationMs: 10000);
      expect(bursts.single.label, 'Rear hand drifts down');
    });

    test('respects the moment cap', () {
      final many = RoundAnalysis(
        overallSummary: 's',
        flaggedMoments: <FlaggedMoment>[
          for (var i = 0; i < 20; i++)
            FlaggedMoment(
              timestampMs: i * 1000.0,
              reason: 'x',
              severity: Severity.minor,
            ),
        ],
      );
      final bursts = CoachingPrompt.keyframeBursts(
        many,
        durationMs: 60000,
        maxMoments: 4,
      );
      expect(bursts, hasLength(4));
    });
  });

  test('keyframeTimestamps are capped', () {
    final many = RoundAnalysis(
      overallSummary: 's',
      flaggedMoments: <FlaggedMoment>[
        for (var i = 0; i < 20; i++)
          FlaggedMoment(
            timestampMs: i * 100.0,
            reason: 'x',
            severity: Severity.minor,
          ),
      ],
    );
    expect(CoachingPrompt.keyframeTimestamps(many, max: 5), hasLength(5));
  });

  group('sampledTimestamps', () {
    test('spans the round, capped at max', () {
      final t = CoachingPrompt.sampledTimestamps(10000);
      expect(t.first, 0);
      expect(t.last, closeTo(10000, 1e-6));
      expect(t.length, lessThanOrEqualTo(40));
      // monotonic increasing
      for (var i = 1; i < t.length; i++) {
        expect(t[i], greaterThan(t[i - 1]));
      }
    });

    test('honours the cap on a long round', () {
      final t = CoachingPrompt.sampledTimestamps(600000, fps: 5, max: 30);
      expect(t.length, 30);
    });

    test('empty for a zero-length round', () {
      expect(CoachingPrompt.sampledTimestamps(0), isEmpty);
    });
  });

  test('keyframeRequest carries the corrections and the images', () {
    final a = analysis();
    final bursts = CoachingPrompt.keyframeBursts(a, durationMs: 10000);
    final images = <VisionImage>[
      VisionImage(bytes: Uint8List.fromList(<int>[0, 0, 0])),
    ];
    final req = CoachingPrompt.keyframeRequest(
      a,
      const DrillContext(),
      bursts,
      images,
    );
    expect(req.userPrompt, contains('Hand drops.'));
    expect(req.userPrompt, contains('orthodox stance'));
    // Explains the burst grouping (7 frames per flagged point).
    expect(req.userPrompt, contains('7 consecutive frames per point'));
    expect(req.images, hasLength(1));
  });

  test('fullVideoRequest sends the pose measurements, style, school and flags '
      'at Gemini\'s max 24 fps, asking for JSON', () {
    final req = CoachingPrompt.fullVideoRequest(
      analysis(),
      const DrillContext(style: Style.phillyShell, school: School.mexican),
      videoPath: '/clips/round.mp4',
      durationSeconds: 120,
    );
    expect(req.videoPath, '/clips/round.mp4');
    expect(req.fps, 24);
    expect(req.responseSchema, CoachingPrompt.fullVideoResponseSchema);
    // Pose analysis payload.
    expect(req.userPrompt, contains('"detected_issues"'));
    expect(req.userPrompt, contains('"metrics"'));
    // Style and school, with what they mean.
    expect(req.userPrompt, contains('Guard style — Philly shell'));
    expect(req.userPrompt, contains('School — Mexican'));
    // The rules' flags as candidates.
    expect(req.userPrompt, contains('Hand drops.'));
    expect(req.userPrompt, contains('Flat-footed.'));
    expect(req.userPrompt, contains('sampled at 24 frames per second'));
    // The checklist and the cap.
    expect(req.systemPrompt, contains('Chin'));
    expect(req.systemPrompt, contains('Rotation'));
    expect(req.systemPrompt, contains('up to 7'));
  });

  test('the response schema caps findings at 7 and requires timestamps', () {
    final issues = CoachingPrompt.fullVideoResponseSchema['properties']!
        as Map<String, Object?>;
    final priority = issues['priority_issues']! as Map<String, Object?>;
    expect(priority['maxItems'], 7);
    final item = priority['items']! as Map<String, Object?>;
    expect(item['required'], containsAll(<String>['timestamps', 'confidence']));
  });

  test('two different corrections at the same instant are both moments', () {
    final a = RoundAnalysis(
      overallSummary: 's',
      correctionPriorities: const <Correction>[
        Correction(
          priority: 1,
          category: SkillCategory.defence,
          description: 'Lead hand drops.',
          exampleTimestampMs: 1000,
        ),
        Correction(
          priority: 2,
          category: SkillCategory.defence,
          description: 'Chin lifts.',
          exampleTimestampMs: 1000,
        ),
      ],
    );
    expect(CoachingPrompt.keyframeMoments(a), hasLength(2));
  });

  test('the moment cap keeps the most important, shown in time order', () {
    final a = RoundAnalysis(
      overallSummary: 's',
      correctionPriorities: <Correction>[
        for (var i = 0; i < 9; i++)
          Correction(
            priority: i + 1,
            category: SkillCategory.defence,
            description: 'c$i',
            // Later priorities earlier in the round.
            exampleTimestampMs: (9 - i) * 1000.0,
          ),
      ],
    );
    final moments = CoachingPrompt.keyframeMoments(a);
    expect(moments, hasLength(7));
    expect(moments.map((m) => m.label), isNot(contains('c7')));
    expect(moments.map((m) => m.label), isNot(contains('c8')));
    for (var i = 1; i < moments.length; i++) {
      expect(moments[i].timestampMs, greaterThan(moments[i - 1].timestampMs));
    }
  });

  test('VideoVisionRequest infers the mime type from the extension', () {
    const mp4 = VideoVisionRequest(systemPrompt: '', userPrompt: '', videoPath: 'a.mp4');
    const mov = VideoVisionRequest(systemPrompt: '', userPrompt: '', videoPath: 'a.MOV');
    expect(mp4.mimeType, 'video/mp4');
    expect(mov.mimeType, 'video/quicktime');
  });

  group('drill checkpoints', () {
    const drill = DrillContext(targetSequence: <int>[1, 2, 3], notes: '1-2-3');

    test('the structured input carries the drill target and its checkpoints',
        () {
      final input = CoachingPrompt.structuredInput(analysis(), drill);
      final target = input['drill_target']! as Map<String, Object?>;
      expect(target['sequence'], <int>[1, 2, 3]);
      expect(target['punches'], <String>['Jab', 'Cross', 'Lead hook']);
      final ids = <Object?>[
        for (final c in target['checkpoints']! as List<Object?>)
          (c! as Map<String, Object?>)['id'],
      ];
      expect(ids, containsAll(<String>[
        'jab_snap_back',
        'cross_lead_hand_home',
        'lead_hook_arm_90',
      ]));
      // Free work has no target.
      expect(CoachingPrompt.structuredInput(analysis(), const DrillContext()),
          isNot(contains('drill_target')));
    });

    test('Full AI review is told to grade the checkpoints first and tag them',
        () {
      final req = CoachingPrompt.fullVideoRequest(
        analysis(),
        drill,
        videoPath: '/clips/drill.mp4',
      );
      expect(req.userPrompt, contains('This round is a drill of 1-2-3'));
      expect(req.userPrompt, contains('[cross_lead_hand_home]'));
      expect(req.userPrompt, contains('the rear shoulder rolls up'));
      expect(req.systemPrompt, contains('drill_target'));
      expect(req.systemPrompt, contains('"checkpoint"'));
      final issues = (CoachingPrompt.fullVideoResponseSchema['properties']!
          as Map<String, Object?>)['priority_issues']! as Map<String, Object?>;
      final props = (issues['items']! as Map<String, Object?>)['properties']!
          as Map<String, Object?>;
      expect(props, contains('checkpoint'));
    });

    test('the key-moment prompt leads with the checkpoints', () {
      final a = analysis();
      final bursts = CoachingPrompt.keyframeBursts(a, durationMs: 10000);
      final req = CoachingPrompt.keyframeRequest(
        a,
        drill,
        bursts,
        <VisionImage>[VisionImage(bytes: Uint8List.fromList(<int>[0]))],
      );
      expect(req.userPrompt, contains('This round is a drill of 1-2-3'));
      expect(req.userPrompt, contains('checkpoints first'));
      // No target, no brief.
      final free = CoachingPrompt.keyframeRequest(
        a,
        const DrillContext(),
        bursts,
        const <VisionImage>[],
      );
      expect(free.userPrompt, isNot(contains('drill of')));
    });
  });
}
