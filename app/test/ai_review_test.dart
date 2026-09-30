import 'package:boxing_coach/analysis/ai_coach_report.dart';
import 'package:boxing_coach/analysis/ai_review.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

AiPriorityIssue issue(
  String code, {
  Severity severity = Severity.moderate,
  double confidence = 0.8,
  List<double> timestamps = const <double>[10],
  String observation = 'Seen.',
  String correction = 'Fix it.',
}) =>
    AiPriorityIssue(
      code: code,
      severity: severity,
      confidence: confidence,
      timestamps: timestamps,
      observation: observation,
      correction: correction,
    );

void main() {
  final rules = RoundAnalysis(
    overallSummary: '40 punches thrown. Main thing to fix: rules top.',
    positiveNotes: const <String>['Clean guard return all round.'],
    correctionPriorities: const <Correction>[
      Correction(
        priority: 1,
        category: SkillCategory.defence,
        description: 'rules top',
        exampleTimestampMs: 5000,
      ),
    ],
    flaggedMoments: const <FlaggedMoment>[
      FlaggedMoment(timestampMs: 7000, reason: 'r', severity: Severity.minor),
    ],
    metrics: const RoundMetrics(punchesThrown: 40),
  );

  group('shownFindings', () {
    test('drops low-confidence findings and those with no time in the round', () {
      final report = AiCoachReport(
        summary: 's',
        priorityIssues: <AiPriorityIssue>[
          issue('GUARD_001', confidence: 0.9),
          issue('GUARD_007', confidence: 0.5), // unsure
          issue('ROT_001', timestamps: const <double>[500]), // past the end
          issue('FOOT_009', timestamps: const <double>[]), // no moment
        ],
      );
      final shown = AiReview.shownFindings(report, durationSeconds: 120);
      expect(shown.map((i) => i.code), <String>['GUARD_001']);
    });

    test('keeps only in-round timestamps', () {
      final report = AiCoachReport(
        summary: 's',
        priorityIssues: <AiPriorityIssue>[
          issue('GUARD_001', timestamps: const <double>[300, 20]),
        ],
      );
      final shown = AiReview.shownFindings(report, durationSeconds: 120);
      expect(shown.single.timestamps, <double>[20]);
    });

    test('orders worst first, then most confident, and caps at 7', () {
      final report = AiCoachReport(
        summary: 's',
        priorityIssues: <AiPriorityIssue>[
          for (var i = 0; i < 9; i++)
            issue('X_$i', confidence: 0.6 + i * 0.04, timestamps: <double>[i * 10.0]),
          issue('BIG', severity: Severity.major, confidence: 0.7),
        ],
      );
      final shown = AiReview.shownFindings(report);
      expect(shown, hasLength(kMaxFindings));
      expect(shown.first.code, 'BIG');
      expect(shown[1].code, 'X_8'); // most confident of the moderates
    });

    test('merges the same fault reported twice at nearly the same time', () {
      final report = AiCoachReport(
        summary: 's',
        priorityIssues: <AiPriorityIssue>[
          issue('GUARD_003', confidence: 0.9, timestamps: const <double>[30]),
          issue('GUARD_003', confidence: 0.7, timestamps: const <double>[30.8]),
          issue('GUARD_003', confidence: 0.7, timestamps: const <double>[60]),
        ],
      );
      expect(AiReview.shownFindings(report), hasLength(2));
    });
  });

  group('apply', () {
    final report = AiCoachReport(
      summary: 'Good rhythm, kid. Two things.',
      strengths: const <String>['Light on your feet.'],
      priorityIssues: <AiPriorityIssue>[
        issue(
          'GUARD_003',
          severity: Severity.major,
          confidence: 0.9,
          timestamps: const <double>[111],
          observation: 'Your lead hand drops on the cross',
          correction: 'Glue it to your temple.',
        ),
        issue(
          'GUARD_007',
          confidence: 0.75,
          timestamps: const <double>[42.5],
          observation: 'Your chin lifts on the jab.',
          correction: 'Tuck it behind your shoulder.',
        ),
        issue('ROT_001', confidence: 0.3),
      ],
    );

    test('the confident findings become the corrections, worst first', () {
      final merged = AiReview.apply(rules, report, durationSeconds: 120);
      expect(merged.correctionPriorities, hasLength(2));
      final top = merged.correctionPriorities.first;
      expect(top.priority, 1);
      expect(top.exampleTimestampMs, 111000);
      expect(top.category, SkillCategory.defence);
      expect(top.description,
          'Your lead hand drops on the cross. Glue it to your temple.');
      expect(merged.correctionPriorities[1].description,
          'Your chin lifts on the jab. Tuck it behind your shoulder.');
    });

    test('the model is the verdict: rule flags go, its strengths replace the '
        "rules' positives, its read is the coaching", () {
      final merged = AiReview.apply(rules, report, durationSeconds: 120);
      expect(merged.flaggedMoments, isEmpty);
      expect(merged.positiveNotes, <String>['Light on your feet.']);
      expect(merged.modelCoaching, 'Good rhythm, kid. Two things.');
      expect(merged.aiReport, same(report));
      expect(merged.overallSummary,
          '40 punches thrown. Main thing to fix: Glue it to your temple. plus 1 '
          'other point(s)');
      // The raw rules output is kept for evaluation.
      expect(merged.metrics.punchesThrown, 40);
    });

    test('keeps the rules positives when the model gives no strengths', () {
      final merged = AiReview.apply(
        rules,
        AiCoachReport(summary: 's', priorityIssues: report.priorityIssues),
      );
      expect(merged.positiveNotes, rules.positiveNotes);
    });

    test('a clean review clears the rules findings', () {
      final merged = AiReview.apply(
        rules,
        const AiCoachReport(summary: 'Clean round.'),
      );
      expect(merged.correctionPriorities, isEmpty);
      expect(merged.overallSummary, contains('Nothing the AI coach'));
    });
  });

  test('categoryFor maps taxonomy families', () {
    expect(AiReview.categoryFor('GUARD_007'), SkillCategory.defence);
    expect(AiReview.categoryFor('REC_001'), SkillCategory.defence);
    expect(AiReview.categoryFor('ROT_001'), SkillCategory.straight);
    expect(AiReview.categoryFor('FOOT_009'), SkillCategory.footwork);
    expect(AiReview.categoryFor('POS_006'), SkillCategory.footwork);
    expect(AiReview.categoryFor('HEAD_001'), SkillCategory.headMovement);
    expect(AiReview.categoryFor('OTHER'), SkillCategory.defence);
  });

  group('drill checkpoints', () {
    test('a report finding keeps its checkpoint id through parsing', () {
      final report = AiCoachReport.tryParse(
        '{"summary":"s","priority_issues":[{"code":"GUARD_003",'
        '"severity":"MEDIUM","confidence":0.8,"timestamps":[3],'
        '"observation":"o","correction":"c","checkpoint":"cross_lead_hand_home"},'
        '{"code":"FOOT_001","severity":"LOW","confidence":0.8,"timestamps":[4],'
        '"observation":"o","correction":"c","checkpoint":""}]}',
      )!;
      expect(report.priorityIssues[0].checkpoint, 'cross_lead_hand_home');
      expect(report.priorityIssues[1].checkpoint, isNull);
    });

    test('a failed checkpoint outranks a general fault of the same severity, '
        'and ties with one a level worse', () {
      final report = AiCoachReport(
        summary: 's',
        priorityIssues: <AiPriorityIssue>[
          issue('FOOT_004', severity: Severity.moderate, confidence: 0.95),
          issue('FOOT_001', severity: Severity.major, confidence: 0.7,
              timestamps: const <double>[20]),
          AiPriorityIssue(
            code: 'GUARD_003',
            severity: Severity.moderate,
            confidence: 0.7,
            timestamps: const <double>[30],
            observation: 'o',
            correction: 'c',
            checkpoint: 'cross_lead_hand_home',
          ),
        ],
      );
      final order = AiReview.shownFindings(report).map((i) => i.code).toList();
      expect(order, <String>['GUARD_003', 'FOOT_001', 'FOOT_004']);
    });
  });
}
