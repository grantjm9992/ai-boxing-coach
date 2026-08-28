import 'dart:convert';

import 'package:boxing_coach/analysis/ai_coach_report.dart';
import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/analysis/session_type.dart';
import 'package:boxing_coach/services/ai/coaching_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 6 (brief §17, §18): strict structured AI I/O.
void main() {
  group('AiCoachReport.tryParse', () {
    const good = '''
{
  "summary": "Solid round, hands mostly honest.",
  "strengths": ["Good jab"],
  "priority_issues": [
    {"code": "GUARD_003", "severity": "HIGH", "confidence": 0.9,
     "timestamps": [12.4], "observation": "Lead drops on the cross",
     "why_it_matters": "Open to the counter", "correction": "Keep it home",
     "suggested_drill": "Shadow the 1-2 returning the hand"}
  ],
  "next_session_focus": ["Guard discipline"]
}''';

    test('parses a valid report', () {
      final report = AiCoachReport.tryParse(good);
      expect(report, isNotNull);
      expect(report!.summary, startsWith('Solid round'));
      expect(report.priorityIssues.single.code, 'GUARD_003');
      expect(report.priorityIssues.single.severity, Severity.major);
      expect(report.strengths, <String>['Good jab']);
    });

    test('tolerates a markdown fence and surrounding prose', () {
      const wrapped = 'Here you go:\n```json\n$good\n```\nHope that helps.';
      expect(AiCoachReport.tryParse(wrapped)?.summary, startsWith('Solid'));
    });

    test('maps HIGH/MEDIUM/LOW severities', () {
      for (final (label, sev) in <(String, Severity)>[
        ('HIGH', Severity.major),
        ('MEDIUM', Severity.moderate),
        ('LOW', Severity.minor),
      ]) {
        final json = '{"summary":"s","priority_issues":[{"code":"X",'
            '"severity":"$label","correction":"c"}]}';
        expect(AiCoachReport.tryParse(json)!.priorityIssues.single.severity, sev);
      }
    });

    test('rejects unschematic output rather than guessing', () {
      // Not JSON at all.
      expect(AiCoachReport.tryParse('Great work, keep it up!'), isNull);
      // Missing summary.
      expect(AiCoachReport.tryParse('{"priority_issues": []}'), isNull);
      // Empty summary.
      expect(AiCoachReport.tryParse('{"summary": "   "}'), isNull);
      // priority_issues not a list.
      expect(AiCoachReport.tryParse('{"summary":"s","priority_issues":{}}'),
          isNull);
      // An issue missing its correction rejects the whole report.
      expect(
        AiCoachReport.tryParse(
            '{"summary":"s","priority_issues":[{"code":"X","severity":"HIGH"}]}'),
        isNull,
      );
      // Unmappable severity.
      expect(
        AiCoachReport.tryParse(
            '{"summary":"s","priority_issues":[{"code":"X","severity":"CRITICAL","correction":"c"}]}'),
        isNull,
      );
    });

    test('round-trips through JSON', () {
      final report = AiCoachReport.tryParse(good)!;
      final back = AiCoachReport.tryParse(jsonEncode(report.toJson()));
      expect(back!.summary, report.summary);
      expect(back.priorityIssues.single.code, 'GUARD_003');
    });
  });

  group('structuredInput (§17)', () {
    test('carries session type, metrics, combinations and split issues', () {
      final analysis = RoundAnalysis(
        overallSummary: 'x',
        sessionType: SessionType.shadowBoxing,
        specificObservations: const <Observation>[
          Observation(
            ruleId: 'guard_return',
            code: 'GUARD_005',
            category: SkillCategory.defence,
            severity: Severity.moderate,
            coachingText: 'hand slow back',
          ),
        ],
        lowConfidenceObservations: const <Observation>[
          Observation(
            ruleId: 'rotation',
            code: 'ROT_001',
            category: SkillCategory.straight,
            severity: Severity.minor,
            coachingText: 'maybe under-rotating',
            confidence: 0.4,
          ),
        ],
        metrics: const RoundMetrics(punchesThrown: 12, guardReturnRate: 0.8),
      );

      final input = CoachingPrompt.structuredInput(
        analysis,
        const DrillContext(),
        durationSeconds: 180,
      );

      final session = input['session'] as Map<String, Object?>;
      expect(session['type'], 'SHADOW_BOXING');
      expect(session['duration_seconds'], 180);
      expect((input['punches'] as Map)['count'], 12);
      final detected = input['detected_issues'] as List<Object?>;
      expect((detected.single as Map)['code'], 'GUARD_005');
      final low = input['low_confidence_observations'] as List<Object?>;
      expect((low.single as Map)['code'], 'ROT_001');
    });
  });

  group('structuredRequest (§18)', () {
    test('asks for JSON and embeds the measurements', () {
      final request = CoachingPrompt.structuredRequest(
        RoundAnalysis(overallSummary: 'x'),
        const DrillContext(),
      );
      expect(request.systemPrompt, contains('JSON'));
      expect(request.systemPrompt, contains('priority_issues'));
      expect(request.userPrompt, contains('"session"'));
    });
  });
}
