import 'dart:convert';
import 'dart:io';

import 'package:boxing_coach/analysis/context.dart';
import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/analysis/rules/guard_return.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_support.dart';

/// The Dart half of the guard-return golden contract: the ported rule must
/// produce the same observations — same failure mode, coaching text, category,
/// severity, highlighted landmark and timing — as the reference engine.
void main() {
  final goldenDir = locateGoldenDir();

  test('golden fixtures are present', () {
    expect(goldenDir, isNotNull);
  });

  if (goldenDir == null) return;

  for (final scenario in goldenScenarios(goldenDir)) {
    final name = scenario.path.split(Platform.pathSeparator).last;
    test('guard return matches golden — $name', () {
      final input =
          jsonDecode(File('${scenario.path}/input.json').readAsStringSync())
              as Map<String, Object?>;
      final expected =
          jsonDecode(File('${scenario.path}/expected.json').readAsStringSync())
              as Map<String, Object?>;

      final sequence = PoseSequence.fromJson(input);
      final context = AnalysisContext(
        sequence: sequence,
        drill: const DrillContext(),
      );
      final got = GuardReturnRule().evaluate(context);
      final want = ((expected['guardReturn'] as List<Object?>?) ?? const <Object?>[])
          .map((e) => e as Map<String, Object?>)
          .toList();

      expect(got.length, want.length, reason: 'observation count for $name');
      for (var i = 0; i < got.length; i++) {
        _expectObservationMatches(got[i], want[i]);
      }
    });
  }
}

void _expectObservationMatches(Observation got, Map<String, Object?> want) {
  expect(got.ruleId, want['ruleId']);
  expect(got.category.value, want['category']);
  expect(got.severity.value, want['severity']);
  expect(got.coachingText, want['coachingText']);
  expect(
    got.highlightLandmarks.map((l) => l.mpIndex).toList(),
    (want['highlight'] as List<Object?>).map((v) => v as int).toList(),
  );

  final wantTs = want['timestampMs'];
  if (wantTs == null) {
    expect(got.timestampMs, isNull);
  } else {
    expect(got.timestampMs, closeTo((wantTs as num).toDouble(), 1e-4));
  }

  final wantMetrics = (want['metrics'] as Map<String, Object?>);
  expect(got.metrics.keys.toSet(), wantMetrics.keys.toSet());
  wantMetrics.forEach((key, value) {
    expect(got.metrics[key], closeTo((value as num).toDouble(), 1e-6));
  });
}
