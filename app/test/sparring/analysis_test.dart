import 'dart:math' as math;

import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/sparring/analysis/fighter_analysis.dart';
import 'package:boxing_coach/sparring/analysis/interaction.dart';
import 'package:boxing_coach/sparring/analysis/sparring_analyzer.dart';
import 'package:boxing_coach/sparring/analysis/sparring_profile.dart';
import 'package:boxing_coach/sparring/model/fighter.dart';
import 'package:boxing_coach/sparring/pose/multi_pose.dart';
import 'package:boxing_coach/sparring/tracking/fighter_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'synthetic.dart';

const Person red = Person(1, topBin: 8, shortsBin: 0);
const Person blue = Person(2, topBin: 10, shortsBin: 5);

/// Reach profile of one punch over 5 frames.
const List<double> _punch = <double>[0.35, 0.8, 1.0, 0.8, 0.35];

double _reach(int frame, List<int> starts) {
  for (final s in starts) {
    final k = frame - s;
    if (k >= 0 && k < _punch.length) return _punch[k];
  }
  return 0;
}

/// Red (left, facing right) jabs at [jabs]; blue (right, facing left) throws
/// a cross 10 frames (0.5 s) after each — a counter. Blue is missing from the
/// frame over [blueMissing].
MultiPoseRound exchangeRound({
  int frames = 200,
  List<int> jabs = const <int>[20, 60, 100, 140],
  int counterDelay = 10,
  (int, int)? blueMissing,
}) {
  final rnd = math.Random(11);
  final crosses = <int>[for (final j in jabs) j + counterDelay];
  return roundOf(<List<PoseCandidate>>[
    for (var i = 0; i < frames; i++)
      <PoseCandidate>[
        body(red, x: 0.25, facing: 1, leadReach: _reach(i, jabs), jitter: rnd),
        if (blueMissing == null || i < blueMissing.$1 || i >= blueMissing.$2)
          body(blue, x: 0.75, facing: -1, rearReach: _reach(i, crosses), jitter: rnd),
      ],
  ]);
}

void main() {
  test('stance is inferred from which foot is nearer the opponent', () {
    final tracked = const FighterTracker().track(exchangeRound());
    expect(
      inferStance(tracked.fighters[FighterLabel.a]!, tracked.fighters[FighterLabel.b]!),
      Stance.orthodox,
    );
    final southpaw = roundOf(<List<PoseCandidate>>[
      for (var i = 0; i < 60; i++)
        <PoseCandidate>[
          body(red, x: 0.25, facing: 1, stance: Stance.southpaw),
          body(blue, x: 0.75, facing: -1),
        ],
    ]);
    final t2 = const FighterTracker().track(southpaw);
    expect(inferStance(t2.fighters[FighterLabel.a]!, t2.fighters[FighterLabel.b]!), Stance.southpaw);
  });

  test('the sparring profile runs only side-view-valid rules', () {
    final profile = sparringProfile();
    for (final id in kSparringRuleIds) {
      expect(profile.enables(id), isTrue, reason: id);
    }
    for (final id in <String>['head_movement', 'footwork', 'body_lean', 'school_adherence']) {
      expect(profile.enables(id), isFalse, reason: id);
    }
    expect(sparringRules().map((r) => r.id).toSet(), kSparringRuleIds);
  });

  group('SparringAnalyzer', () {
    test("each fighter's punches are theirs, with the right hand", () {
      final tracked = const FighterTracker().track(exchangeRound());
      final analysis = const SparringAnalyzer().analyse(tracked);
      final a = analysis.fighter(FighterLabel.a);
      final b = analysis.fighter(FighterLabel.b);
      expect(a.punchCount, 4);
      expect(b.punchCount, 4);
      expect(a.punches.every((p) => p.side == Side.left && p.by == FighterLabel.a), isTrue);
      expect(b.punches.every((p) => p.side == Side.right && p.by == FighterLabel.b), isTrue);
      expect(a.stance, Stance.orthodox);
      expect(a.stanceInferred, isTrue);
      expect(a.punchesPerMinute, greaterThan(0));
    });

    test('interaction: exchanges, counters and range', () {
      final tracked = const FighterTracker().track(exchangeRound());
      final analysis = const SparringAnalyzer().analyse(tracked);
      final i = analysis.interaction;
      expect(i.exchanges, hasLength(4));
      expect(i.exchanges.every((e) => e.startedBy == FighterLabel.a), isTrue);
      expect(i.exchanges.every((e) => e.finishedBy == FighterLabel.b), isTrue);
      expect(i.fighters[FighterLabel.b]!.counters, 4);
      expect(i.fighters[FighterLabel.a]!.counters, 0);
      expect(i.fighters[FighterLabel.a]!.exchangesStarted, 4);
      final mid = i.bandSeconds[DistanceBand.mid]!;
      expect(mid, greaterThan(i.bandSeconds[DistanceBand.long]!));
      expect(mid, greaterThan(i.bandSeconds[DistanceBand.inside]!));
      expect(i.analysedSeconds, closeTo(10, 0.5));
      expect(i.distanceTimeline, isNotEmpty);
    });

    test("a punch while the fighter couldn't be resolved is dropped, not guessed", () {
      final tracked = const FighterTracker().track(exchangeRound(blueMissing: (100, 125)));
      final analysis = const SparringAnalyzer().analyse(tracked);
      expect(analysis.fighter(FighterLabel.b).punchCount, 3);
      expect(analysis.fighter(FighterLabel.a).punchCount, 4);
      expect(analysis.unresolvedMs[FighterLabel.b], greaterThan(1000));
    });

    test('a barely tracked fighter gets a note, not made-up numbers', () {
      final round = roundOf(<List<PoseCandidate>>[
        for (var i = 0; i < 100; i++)
          <PoseCandidate>[
            body(red, x: 0.25, facing: 1),
            if (i < 20) body(blue, x: 0.75, facing: -1),
          ],
      ]);
      final analysis = const SparringAnalyzer().analyse(const FighterTracker().track(round));
      final b = analysis.fighter(FighterLabel.b);
      expect(b.note, isNotNull);
      expect(b.punchCount, 0);
    });

    test('the profile stance is used when given', () {
      final tracked = const FighterTracker().track(exchangeRound());
      final analysis = const SparringAnalyzer().analyse(
        tracked,
        setups: const <FighterLabel, FighterSetup>{
          FighterLabel.a: FighterSetup(stance: Stance.southpaw),
        },
      );
      expect(analysis.fighter(FighterLabel.a).stance, Stance.southpaw);
      expect(analysis.fighter(FighterLabel.a).stanceInferred, isFalse);
    });

    test('round-trips through JSON', () {
      final tracked = const FighterTracker().track(exchangeRound());
      final analysis = const SparringAnalyzer().analyse(tracked);
      final back = SparringRoundAnalysis.fromJson(analysis.toJson());
      expect(back.fighter(FighterLabel.a).punchCount, 4);
      expect(back.interaction.exchanges.length, 4);
      expect(back.interaction.fighters[FighterLabel.b]!.counters, 4);
      expect(back.unresolvedMs.keys, FighterLabel.values.toSet());
    });
  });

  test('findingsFrom keeps confident faults, one per code, worst first', () {
    Observation o(String code, Severity s, double c, [double? t]) => Observation(
      ruleId: code.toLowerCase(),
      code: code,
      category: SkillCategory.defence,
      severity: s,
      coachingText: code,
      confidence: c,
      timestampMs: t,
    );
    final findings = FighterAnalyzer.findingsFrom(<Observation>[
      o('GUARD_001', Severity.minor, 0.9, 1000),
      o('GUARD_002', Severity.major, 0.8, 2000),
      o('GUARD_002', Severity.major, 0.7, 3000),
      o('ROT_001', Severity.moderate, 0.4, 4000), // unsure
      o('', Severity.positive, 1),
    ]);
    expect(findings.map((f) => f.code), <String>['GUARD_002', 'GUARD_001']);
    expect(findings.first.timestampMs, 2000);
    expect(findings.every((f) => f.source == 'rules'), isTrue);
  });
}
