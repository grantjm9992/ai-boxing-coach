import 'dart:io';

import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/analysis/session_type.dart';
import 'package:boxing_coach/domain/shadow_round.dart';
import 'package:boxing_coach/domain/skill_category.dart' as sc;
import 'package:boxing_coach/services/session_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// A standalone shadow round persists to History/Progress like a guided session.
void main() {
  RoundAnalysis analysis() => RoundAnalysis(
    overallSummary: 'Solid shadow round.',
    sessionType: SessionType.shadowBoxing,
    correctionPriorities: const <Correction>[
      Correction(
        priority: 1,
        category: SkillCategory.defence,
        description: 'Keep the lead hand up between shots.',
      ),
    ],
    metrics: const RoundMetrics(punchesThrown: 40, guardReturnRate: 0.7),
  );

  test('shadowSessionRecord attributes time and carries the round summary', () {
    final at = DateTime(2026, 8, 29, 10);
    final record = shadowSessionRecord(
      analysis(),
      durationMs: 180000, // 3 min
      sessionId: 'shadow_1',
      completedAt: at,
    );

    expect(record.templateName, 'Shadow boxing');
    expect(record.roundCount, 1);
    expect(record.workSeconds, 180);
    // Category seconds are attributed and land under real category keys.
    expect(record.categorySeconds[sc.SkillCategory.footwork.key], 36); // 0.20*180
    expect(record.categorySeconds[sc.SkillCategory.defence.key], 27); // 0.15*180
    expect(record.categoryBreakdown.keys, contains(sc.SkillCategory.footwork));
    // The round summary carries the analysis.
    final round = record.rounds.single;
    expect(round.summary, 'Solid shadow round.');
    expect(round.topCorrection, startsWith('Keep the lead hand up'));
    expect(round.punchesThrown, 40);
  });

  test('saved shadow round shows up in history', () async {
    final dir = await Directory.systemTemp.createTemp('shadow_hist');
    addTearDown(() => dir.delete(recursive: true));
    final store = SessionHistoryStore(baseDir: dir);

    final record = shadowSessionRecord(
      analysis(),
      durationMs: 120000,
      sessionId: 'shadow_2',
      completedAt: DateTime(2026, 8, 29, 11),
    );
    await store.save(record);

    final listed = await store.list();
    expect(listed.map((r) => r.sessionId), contains('shadow_2'));
    expect(listed.single.templateName, 'Shadow boxing');
  });
}
