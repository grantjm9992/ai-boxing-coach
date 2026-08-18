import 'dart:typed_data';

import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/services/ai/coaching_prompt.dart';
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
    final images = <VisionImage>[
      VisionImage(bytes: Uint8List.fromList(<int>[0, 0, 0])),
    ];
    final req = CoachingPrompt.keyframeRequest(
      analysis(),
      const DrillContext(),
      images,
    );
    expect(req.userPrompt, contains('Hand drops.'));
    expect(req.userPrompt, contains('orthodox stance'));
    expect(req.images, hasLength(1));
  });

  test('fullFrameRequest mentions the frame count', () {
    final images = <VisionImage>[
      for (var i = 0; i < 5; i++) VisionImage(bytes: Uint8List.fromList(<int>[0, 0, 0])),
    ];
    final req = CoachingPrompt.fullFrameRequest(const DrillContext(), images);
    expect(req.userPrompt, contains('5 frames'));
    expect(req.images, hasLength(5));
  });
}
