import 'package:boxing_coach/analysis/combination.dart';
import 'package:boxing_coach/analysis/combination_analysis.dart';
import 'package:boxing_coach/analysis/drill_matching.dart';
import 'package:boxing_coach/analysis/punch.dart';
import 'package:boxing_coach/data/combination_library.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 5 (brief §14, §15): the combination library + drill evaluation.
void main() {
  group('CombinationLibrary', () {
    test('ids are unique and every entry is well-formed', () {
      final ids = <String>{};
      for (final combo in CombinationLibrary.all) {
        expect(ids.add(combo.id), isTrue, reason: 'duplicate id ${combo.id}');
        expect(combo.numbers, isNotEmpty);
        expect(combo.numberLabel, combo.numbers.join('-'));
        expect(combo.punchNames.length, combo.numbers.length);
        // Starter set is punches only — no unknown/defensive slots.
        expect(combo.numbers, isNot(contains(unknownPunchNumber)));
      }
    });

    test('byId finds and misses correctly', () {
      expect(CombinationLibrary.byId('combo_1_2_3')?.numbers, <int>[1, 2, 3]);
      expect(CombinationLibrary.byId('nope'), isNull);
    });

    test('punchNameForNumber maps the numbering', () {
      expect(punchNameForNumber(1), 'Jab');
      expect(punchNameForNumber(4), 'Rear hook');
      expect(punchNameForNumber(unknownPunchNumber), 'Unknown');
    });
  });

  group('evaluateDrill', () {
    test('scores matched attempts and ignores mis-thrown ones in the average', () {
      final result = evaluateDrill(<int>[1, 2, 3], <CombinationAnalysis>[
        _analysis(<int>[1, 2, 3], 90), // match
        _analysis(<int>[1, 2], 100), // wrong sequence — excluded from avg
        _analysis(<int>[1, 2, 3], 70), // match
      ]);
      expect(result.totalAttempts, 3);
      expect(result.matchedCount, 2);
      expect(result.matchRate, closeTo(2 / 3, 1e-9));
      expect(result.averageScore, 80); // (90 + 70) / 2, the 100 is excluded
    });

    test('no matches leaves the average null', () {
      final result = evaluateDrill(<int>[1, 2, 3], <CombinationAnalysis>[
        _analysis(<int>[1, 2], 100),
      ]);
      expect(result.matchedCount, 0);
      expect(result.matchRate, 0);
      expect(result.averageScore, isNull);
    });

    test('no attempts is an empty, safe result', () {
      final result = evaluateDrill(<int>[1, 2], const <CombinationAnalysis>[]);
      expect(result.totalAttempts, 0);
      expect(result.matchRate, 0);
      expect(result.averageScore, isNull);
    });
  });
}

CombinationAnalysis _analysis(List<int> seq, int score) => CombinationAnalysis(
  combination: Combination(
    startMs: 0,
    endMs: 500,
    sequence: seq,
    types: <PunchType>[for (final _ in seq) PunchType.straight],
    confidence: 1.0,
    punchIndices: <int>[for (var i = 0; i < seq.length; i++) i],
  ),
  score: score,
);
