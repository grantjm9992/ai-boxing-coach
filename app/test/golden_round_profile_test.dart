import 'dart:convert';
import 'dart:io';

import 'package:boxing_coach/analysis/context.dart';
import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/analysis/schools.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_support.dart';

/// The Dart half of the round-profile + national-schools golden contract: the
/// ported round profile, feature values and school ranking must match the
/// reference on every fixture.
void main() {
  final goldenDir = locateGoldenDir();

  test('golden fixtures are present', () => expect(goldenDir, isNotNull));
  if (goldenDir == null) return;

  for (final scenario in goldenScenarios(goldenDir)) {
    final name = scenario.path.split(Platform.pathSeparator).last;
    test('round profile + schools match golden — $name', () {
      final input =
          jsonDecode(File('${scenario.path}/input.json').readAsStringSync())
              as Map<String, Object?>;
      final expected =
          jsonDecode(File('${scenario.path}/expected.json').readAsStringSync())
              as Map<String, Object?>;

      final sequence = PoseSequence.fromJson(input);
      final context =
          AnalysisContext(sequence: sequence, drill: const DrillContext());

      // Round profile (rounded, per as_dict).
      final profile = context.roundProfile.asDict();
      final wantProfile = expected['roundProfile'] as Map<String, Object?>;
      expect(profile.keys.toSet(), wantProfile.keys.toSet());
      wantProfile.forEach((k, v) {
        expect(profile[k], closeTo((v as num).toDouble(), 1e-6), reason: '$name.$k');
      });

      // Feature values.
      final features =
          roundFeatureValues(context.roundProfile, context.punches, Stance.orthodox);
      final wantFeatures = expected['featureValues'] as Map<String, Object?>;
      expect(features.keys.toSet(), wantFeatures.keys.toSet());
      wantFeatures.forEach((k, v) {
        expect(features[k], closeTo((v as num).toDouble(), 1e-6), reason: '$name.$k');
      });

      // School ranking (order + scores).
      final ranking = classifySchool(features);
      final wantRanking = (expected['schoolRanking'] as List<Object?>)
          .map((e) => e as List<Object?>)
          .toList();
      expect(ranking.length, wantRanking.length);
      for (var i = 0; i < ranking.length; i++) {
        expect(ranking[i].$1.value, wantRanking[i][0]);
        expect(ranking[i].$2, closeTo((wantRanking[i][1] as num).toDouble(), 1e-6));
      }
    });
  }
}
