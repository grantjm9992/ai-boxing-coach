import 'dart:io';

import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/domain/session_record.dart';
import 'package:boxing_coach/domain/skill_category.dart' as dom;
import 'package:boxing_coach/services/analysis_store.dart';
import 'package:boxing_coach/services/session_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoundAnalysis JSON', () {
    test('round-trips observations, corrections, metrics and flags', () {
      final analysis = RoundAnalysis(
        overallSummary: 'One thing to fix: guard.',
        specificObservations: <Observation>[
          Observation(
            ruleId: 'guard_return',
            category: SkillCategory.defence,
            severity: Severity.moderate,
            coachingText: 'Hand drops.',
            timestampMs: 733.3,
            metrics: const <String, double>{'peak_reach': 1.5},
            highlightLandmarks: const <Landmark>[Landmark.leftWrist],
          ),
        ],
        positiveNotes: const <String>['Nice footwork.'],
        correctionPriorities: <Correction>[
          const Correction(
            priority: 1,
            category: SkillCategory.defence,
            description: 'Hand drops.',
            suggestedDrill: 'jab-return',
            exampleTimestampMs: 733.3,
            highlightLandmarks: <Landmark>[Landmark.leftWrist],
          ),
        ],
        metrics: const RoundMetrics(
          punchesThrown: 3,
          guardReturnRate: 0.67,
          punchMix: <String, int>{'jab': 2, 'cross': 1},
          values: <String, double>{'body_scale': 0.2},
        ),
        flaggedMoments: const <FlaggedMoment>[
          FlaggedMoment(
            timestampMs: 733.3,
            reason: 'Hand drops.',
            severity: Severity.moderate,
          ),
        ],
      );

      final back = RoundAnalysis.fromJson(analysis.toJson());
      expect(back.overallSummary, analysis.overallSummary);
      expect(back.specificObservations.single.ruleId, 'guard_return');
      expect(back.specificObservations.single.highlightLandmarks,
          <Landmark>[Landmark.leftWrist]);
      expect(back.correctionPriorities.single.suggestedDrill, 'jab-return');
      expect(back.metrics.punchesThrown, 3);
      expect(back.metrics.guardReturnRate, closeTo(0.67, 1e-9));
      expect(back.metrics.punchMix['jab'], 2);
      expect(back.flaggedMoments.single.severity, Severity.moderate);
    });
  });

  group('AnalysisStore', () {
    late Directory tempDir;
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('analysis_store');
    });
    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('saves and loads analysis + pose for a round', () async {
      final store = AnalysisStore(baseDir: tempDir);
      final analysis = RoundAnalysis(overallSummary: 'ok');
      final seq = PoseSequence(
        frames: <PoseFrame>[
          PoseFrame(
            index: 0,
            timestampMs: 0,
            keypoints: <Landmark, Keypoint>{
              Landmark.nose: const Keypoint(0.5, 0.3),
            },
          ),
        ],
        fps: 30,
      );

      await store.save('s1', 4, analysis: analysis, sequence: seq);

      final loadedAnalysis = await store.loadAnalysis('s1', 4);
      final loadedPose = await store.loadPose('s1', 4);
      expect(loadedAnalysis?.overallSummary, 'ok');
      expect(loadedPose?.frames.single.get(Landmark.nose)?.x, closeTo(0.5, 1e-9));
      expect(await store.loadAnalysis('s1', 99), isNull);
    });
  });

  group('SessionHistoryStore', () {
    late Directory tempDir;
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('history_store');
    });
    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    SessionRecord record(String id, DateTime when, Map<String, int> cats) =>
        SessionRecord(
          sessionId: id,
          templateName: 'Test',
          completedAt: when,
          totalSeconds: 1200,
          workSeconds: 600,
          roundCount: 3,
          categorySeconds: cats,
        );

    test('save/list round-trips, newest first', () async {
      final store = SessionHistoryStore(baseDir: tempDir);
      await store.save(record('a', DateTime(2026, 8, 2), {'defence': 60}));
      await store.save(record('b', DateTime(2026, 8, 9), {'footwork': 120}));

      final list = await store.list();
      expect(list.map((r) => r.sessionId), <String>['b', 'a']);
    });

    test('weeklyBalance sums only sessions within the window', () async {
      final now = DateTime(2026, 8, 10, 12);
      final store = SessionHistoryStore(baseDir: tempDir, now: () => now);
      await store.save(record('recent1', now.subtract(const Duration(days: 1)),
          {'defence': 100, 'footwork': 50}));
      await store.save(record('recent2', now.subtract(const Duration(days: 3)),
          {'defence': 40}));
      await store.save(record('old', now.subtract(const Duration(days: 9)),
          {'defence': 999}));

      final weekly = await store.weeklyBalance();
      expect(weekly['defence'], 140); // 100 + 40, old excluded
      expect(weekly['footwork'], 50);
    });

    test('aggregateCategorySeconds is a pure sum', () {
      final totals = SessionHistoryStore.aggregateCategorySeconds(<SessionRecord>[
        record('x', DateTime(2026), {'defence': 30, 'jab': 10}),
        record('y', DateTime(2026), {'defence': 20}),
      ]);
      expect(totals, <String, int>{'defence': 50, 'jab': 10});
    });

    test('categoryBreakdown maps keys back to skill categories', () {
      final r = record('z', DateTime(2026), {'defence': 60, 'footwork': 30});
      final breakdown = r.categoryBreakdown;
      expect(breakdown[dom.SkillCategory.defence], const Duration(seconds: 60));
      expect(breakdown[dom.SkillCategory.footwork], const Duration(seconds: 30));
    });
  });
}
