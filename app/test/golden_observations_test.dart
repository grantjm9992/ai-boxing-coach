import 'dart:convert';
import 'dart:io';

import 'package:boxing_coach/analysis/context.dart';
import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/engine.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_support.dart';

/// The Dart half of the rule-engine golden contract: running the four v0.5 rules
/// over each fixture must produce the same sorted observations — failure modes,
/// coaching text, categories, severities, highlighted landmarks, timing — as the
/// reference engine. This one assertion covers all four rules and the engine's
/// worst-first ordering at once.
void main() {
  final goldenDir = locateGoldenDir();

  test('golden fixtures are present', () {
    expect(goldenDir, isNotNull);
  });

  if (goldenDir == null) return;

  for (final scenario in goldenScenarios(goldenDir)) {
    final name = scenario.path.split(Platform.pathSeparator).last;
    test('engine observations match golden — $name', () {
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
      final got = RuleEngine(defaultRules()).run(context);
      final want = ((expected['observations'] as List<Object?>?) ??
              const <Object?>[])
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

  final wantMetrics = want['metrics'] as Map<String, Object?>;
  expect(got.metrics.keys.toSet(), wantMetrics.keys.toSet());
  // Golden metrics are rounded (3–6 dp); the Dart values are full precision, so
  // a small tolerance covers the rounding without hiding real drift.
  wantMetrics.forEach((key, value) {
    expect(got.metrics[key], closeTo((value as num).toDouble(), 1e-3));
  });
}
