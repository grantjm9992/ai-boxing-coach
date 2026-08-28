import 'dart:convert';
import 'dart:io';

import 'package:boxing_coach/analysis/context.dart';
import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/engine.dart';
import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/analysis/school.dart';
import 'package:boxing_coach/analysis/style_profiles.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_support.dart';

/// The Dart half of the style/school golden contract: the profile plumbing
/// (gated rules, retuned thresholds, school overrides, school-adherence) must
/// produce the same observations as the reference for each case.
void main() {
  final goldenDir = locateGoldenDir();
  if (goldenDir == null) {
    test('golden fixtures present', () => fail('run emit_golden_fixtures.py'));
    return;
  }

  final casesFile = File('${goldenDir.path}/_style_cases.json');
  test('style cases present', () => expect(casesFile.existsSync(), isTrue));
  if (!casesFile.existsSync()) return;

  final cases = (jsonDecode(casesFile.readAsStringSync())
      as Map<String, Object?>)['cases'] as List<Object?>;

  for (final raw in cases) {
    final c = raw as Map<String, Object?>;
    final label = '${c['fixture']}-${c['style']}-${c['school']}';
    test('style case matches golden — $label', () {
      final input = jsonDecode(
        File('${goldenDir.path}/${c['fixture']}/input.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final sequence = PoseSequence.fromJson(input);

      final stance =
          c['stance'] == 'southpaw' ? Stance.southpaw : Stance.orthodox;
      final style =
          Style.values.firstWhere((s) => s.value == c['style']);
      final school = School.fromValue(c['school'] as String?);

      final drill = DrillContext(stance: stance, style: style, school: school);
      final context = AnalysisContext(
        sequence: sequence,
        drill: drill,
        styleProfile: resolveProfile(style, school),
      );
      // Frozen to the v0.5 rule set (Dart↔Python golden parity contract).
      final got = RuleEngine(v05Rules()).run(context);
      final want = (c['observations'] as List<Object?>)
          .map((e) => e as Map<String, Object?>)
          .toList();

      expect(got.length, want.length, reason: label);
      for (var i = 0; i < got.length; i++) {
        _expectObs(got[i], want[i]);
      }
    });
  }
}

void _expectObs(Observation got, Map<String, Object?> want) {
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
  wantMetrics.forEach((k, v) {
    expect(got.metrics[k], closeTo((v as num).toDouble(), 1e-3));
  });
}
