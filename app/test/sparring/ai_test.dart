import 'dart:convert';
import 'dart:math' as math;

import 'package:boxing_coach/analysis/ai_coach_report.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/services/ai/video_vision_model.dart';
import 'package:boxing_coach/services/ai/vision_model.dart';
import 'package:boxing_coach/sparring/ai/sparring_coach.dart';
import 'package:boxing_coach/sparring/ai/sparring_prompt.dart';
import 'package:boxing_coach/sparring/ai/sparring_report.dart';
import 'package:boxing_coach/sparring/ai/sparring_review.dart';
import 'package:boxing_coach/sparring/analysis/sparring_analyzer.dart';
import 'package:boxing_coach/sparring/model/fighter.dart';
import 'package:boxing_coach/sparring/model/sparring_session.dart';
import 'package:boxing_coach/sparring/pose/multi_pose.dart';
import 'package:boxing_coach/sparring/tracking/fighter_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'synthetic.dart';

const Person red = Person(1, topBin: 8, shortsBin: 0);
const Person blue = Person(2, topBin: 10, shortsBin: 5);

Map<String, Object?> issue(String code, {double confidence = 0.8, List<double> at = const <double>[3]}) =>
    <String, Object?>{
      'code': code,
      'severity': 'HIGH',
      'confidence': confidence,
      'timestamps': at,
      'observation': 'Seen $code',
      'correction': 'Fix $code.',
    };

String reportJson({List<Map<String, Object?>>? aIssues}) => jsonEncode(<String, Object?>{
  'summary': 'Good round.',
  'fighter_a': <String, Object?>{
    'summary': 'You led well.',
    'strengths': <String>['Sharp jab'],
    'priority_issues': aIssues ?? <Object?>[issue('GUARD_002')],
    'landed_estimate': 6,
    'patterns': <String>['Jab, then reset'],
  },
  'fighter_b': <String, Object?>{
    'summary': 'Countered well.',
    'strengths': <String>[],
    'priority_issues': <Object?>[issue('GUARD_001', at: <double>[5])],
  },
  'exchanges': <Object?>[
    <String, Object?>{'start': 1.0, 'end': 2.5, 'started_by': 'A', 'summary': 'Jab, cross back.'},
  ],
  'defence': <Object?>[
    <String, Object?>{'time': 1.6, 'defender': 'A', 'response': 'block', 'verdict': 'good'},
  ],
});

(TrackedRound, SparringRoundAnalysis) sample() {
  final rnd = math.Random(2);
  final round = roundOf(<List<PoseCandidate>>[
    for (var i = 0; i < 120; i++)
      <PoseCandidate>[
        body(red, x: 0.25, facing: 1, jitter: rnd),
        body(blue, x: 0.75, facing: -1, jitter: rnd),
      ],
  ]);
  final tracked = const FighterTracker().track(round);
  return (tracked, const SparringAnalyzer().analyse(tracked));
}

void main() {
  group('SparringAiReport', () {
    test('parses both fighters, exchanges and defence', () {
      final report = SparringAiReport.tryParse(reportJson())!;
      expect(report.summary, 'Good round.');
      expect(report.fighter(FighterLabel.a).issues.single.code, 'GUARD_002');
      expect(report.fighter(FighterLabel.a).landedEstimate, 6);
      expect(report.exchanges.single.startedBy, FighterLabel.a);
      expect(report.defence.single.defender, FighterLabel.a);
    });

    test('accepts fenced JSON; rejects prose and a missing fighter', () {
      expect(SparringAiReport.tryParse('```json\n${reportJson()}\n```'), isNotNull);
      expect(SparringAiReport.tryParse('Great round, kid.'), isNull);
      expect(SparringAiReport.tryParse(jsonEncode(<String, Object?>{'summary': 's', 'fighter_a': <String, Object?>{}})), isNull);
    });

    test('swapped() exchanges A and B everywhere', () {
      final swapped = SparringAiReport.tryParse(reportJson())!.swapped();
      expect(swapped.fighter(FighterLabel.b).issues.single.code, 'GUARD_002');
      expect(swapped.exchanges.single.startedBy, FighterLabel.b);
      expect(swapped.defence.single.defender, FighterLabel.b);
    });

    test('round-trips through toJson', () {
      final report = SparringAiReport.tryParse(reportJson())!;
      final back = SparringAiReport.fromJson(jsonDecode(jsonEncode(report.toJson())) as Map<String, Object?>);
      expect(back.fighter(FighterLabel.a).issues.single.severity, Severity.major);
      expect(back.exchanges.length, 1);
    });
  });

  group('SparringReview', () {
    test("the AI's confident findings replace each fighter's", () {
      final (_, analysis) = sample();
      final report = SparringAiReport.tryParse(reportJson(aIssues: <Map<String, Object?>>[
        issue('GUARD_002'),
        issue('GUARD_002', at: <double>[3.4]), // same moment
        issue('ROT_001', confidence: 0.4), // unsure
        issue('BAL_001', at: <double>[999]), // outside the round
        issue('FOOT_009', confidence: 0.7, at: <double>[4]),
      ]))!;
      final reviewed = SparringReview.apply(analysis, report);
      final a = reviewed.fighter(FighterLabel.a);
      expect(a.findings.map((f) => f.code), <String>['GUARD_002', 'FOOT_009']);
      expect(a.findings.first.source, 'ai');
      expect(a.findings.first.timestampMs, 3000);
      expect(a.findings.first.text, 'Seen GUARD_002. Fix GUARD_002.');
      expect(a.summary, 'You led well.');
      expect(a.strengths, <String>['Sharp jab']);
      expect(reviewed.fighter(FighterLabel.b).findings.single.code, 'GUARD_001');
      expect(reviewed.ai, isNotNull);
      // Measurements stay on-device.
      expect(a.punchCount, analysis.fighter(FighterLabel.a).punchCount);
    });

    test('caps at seven per fighter', () {
      final issues = <AiPriorityIssue>[
        for (var i = 0; i < 10; i++)
          AiPriorityIssue(
            code: 'X_$i',
            severity: Severity.moderate,
            confidence: 0.9,
            timestamps: <double>[i.toDouble()],
            observation: 'o',
            correction: 'c',
          ),
      ];
      expect(SparringReview.shownFindings(issues), hasLength(7));
    });
  });

  group('SparringPrompt', () {
    test('identifies both fighters by kit, position and box track', () {
      final (tracked, analysis) = sample();
      final session = SparringSession(
        id: 's1',
        createdAt: DateTime(2026, 10, 1),
        identified: true,
        partnerName: 'Dani',
        youKit: 'black top, red shorts',
        partnerKit: 'white top, blue shorts',
      );
      final request = SparringPrompt.request(
        session: session,
        roundNumber: 2,
        tracked: tracked,
        analysis: analysis,
        videoPath: '/tmp/clip.mp4',
      );
      final prompt = request.userPrompt;
      expect(prompt, contains('Fighter A — the user'));
      expect(prompt, contains('Fighter B — Dani'));
      expect(prompt, contains('Wearing: black top, red shorts'));
      expect(prompt, contains('Starts on the left'));
      expect(prompt, contains('shorts red/orange'));
      expect(prompt, contains('Fighter A: 0.0: '));
      expect(prompt, contains('"fighter_b"'));
      expect(request.fps, kFullReviewFps);
      expect(request.maxTokens, 12000);
      final props = request.responseSchema!['properties']! as Map<String, Object?>;
      expect(props.keys, containsAll(<String>['summary', 'fighter_a', 'fighter_b', 'exchanges', 'defence']));
      expect(request.systemPrompt, contains('Never attribute'));
    });

    test('flags windows the tracker could not resolve', () {
      final round = roundOf(<List<PoseCandidate>>[
        for (var i = 0; i < 100; i++)
          <PoseCandidate>[
            body(red, x: 0.25, facing: 1),
            if (i < 40 || i >= 60) body(blue, x: 0.75, facing: -1),
          ],
      ]);
      final tracked = const FighterTracker().track(round);
      final windows = SparringPrompt.unresolvedWindows(tracked);
      expect(windows, isNotEmpty);
      expect(windows.first, startsWith('2.0'));
      expect(SparringPrompt.boxTrack(tracked, FighterLabel.b), contains('2.5: -'));
    });
  });

  group('SparringCoach', () {
    test('folds a parsed report in; an unreadable answer is an error', () async {
      final (tracked, analysis) = sample();
      final request = SparringPrompt.request(
        session: SparringSession(id: 's', createdAt: DateTime(2026)),
        roundNumber: 1,
        tracked: tracked,
        analysis: analysis,
        videoPath: '/tmp/x.mp4',
      );
      final good = SparringCoach(model: FakeVideoVisionModel(response: reportJson()));
      final reviewed = await good.review(request, analysis);
      expect(reviewed.ai, isNotNull);

      final bad = SparringCoach(model: FakeVideoVisionModel(response: 'Nice work.'));
      await expectLater(bad.review(request, analysis), throwsA(isA<VisionModelException>()));
    });
  });
}
