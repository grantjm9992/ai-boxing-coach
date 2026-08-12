import 'dart:convert';
import 'dart:io';

import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/analysis/pose_only_adapter.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/analysis/school.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_support.dart';

/// Unit tests for the deterministic synthesis in [PoseOnlyAdapter] — how the
/// engine's observations become a spoken summary, prioritised corrections,
/// positive notes, metrics and flagged moments. The rule outputs themselves are
/// covered cross-language by the golden tests; this checks the assembly.
void main() {
  final goldenDir = locateGoldenDir();
  if (goldenDir == null) {
    test('golden fixtures present', () => fail('run emit_golden_fixtures.py'));
    return;
  }

  PoseSequence load(String name) {
    final input =
        jsonDecode(File('${goldenDir.path}/$name/input.json').readAsStringSync())
            as Map<String, Object?>;
    return PoseSequence.fromJson(input);
  }

  final adapter = PoseOnlyAdapter();

  test('a dropped-guard jab produces a defence correction and a flagged moment', () {
    final analysis = adapter.analyse(load('dropped_guard_jab'), const DrillContext());

    expect(analysis.metrics.punchesThrown, 1);
    expect(analysis.correctionPriorities, isNotEmpty);
    final top = analysis.correctionPriorities.first;
    expect(top.priority, 1);
    expect(top.category, SkillCategory.defence);
    expect(top.suggestedDrill, isNotNull);
    expect(analysis.flaggedMoments, isNotEmpty);
    expect(analysis.overallSummary, contains('Main thing to fix'));
    // A dropped guard means the guard-return rate is below 1.0.
    expect(analysis.metrics.guardReturnRate, lessThan(1.0));
  });

  test('a clean jab reads as a clean round with a positive note', () {
    final analysis = adapter.analyse(load('clean_jab'), const DrillContext());

    expect(analysis.correctionPriorities, isEmpty);
    expect(analysis.positiveNotes, isNotEmpty);
    expect(analysis.overallSummary, contains('Clean round'));
    expect(analysis.metrics.guardReturnRate, 1.0);
    expect(analysis.metrics.punchMix['jab'], 1);
  });

  test('corrections are de-duplicated to one per category, worst first', () {
    // static_feet trips footwork (moderate) and head_movement (minor).
    final analysis = adapter.analyse(load('static_feet'), const DrillContext());

    final categories =
        analysis.correctionPriorities.map((c) => c.category).toList();
    expect(categories, categories.toSet().toList(),
        reason: 'no category should repeat');
    expect(analysis.correctionPriorities.first.category, SkillCategory.footwork,
        reason: 'moderate footwork outranks minor head movement');
    // Priorities are 1..n in order.
    for (var i = 0; i < analysis.correctionPriorities.length; i++) {
      expect(analysis.correctionPriorities[i].priority, i + 1);
    }
  });

  test('metrics carry body scale, round-profile features and punch mix', () {
    final analysis = adapter.analyse(load('clean_jab'), const DrillContext());
    expect(analysis.metrics.values['body_scale'], closeTo(0.2, 1e-4));
    // Full-parity metrics now include the round-profile feature values...
    expect(analysis.metrics.values.containsKey('output_per_min'), isTrue);
    expect(analysis.metrics.values.containsKey('mobility'), isTrue);
    // ...and the named punch mix.
    expect(analysis.metrics.punchMix['jab'], 1);
  });

  test('a school drill adds school-adherence coaching', () {
    // Mexican expects volume/body work; a single clean jab misses those.
    final analysis =
        adapter.analyse(load('clean_jab'), const DrillContext(school: School.mexican));
    expect(
      analysis.correctionPriorities.any((c) => c.category == SkillCategory.rhythm ||
          c.category == SkillCategory.hooks),
      isTrue,
    );
  });
}
