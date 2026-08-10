import 'dart:convert';
import 'dart:io';

import 'package:boxing_coach/analysis/features.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_support.dart';

/// The Dart half of the punch-detection golden contract: `PunchDetector` must
/// find the same punches — same boundaries, same motion class — the reference
/// engine recorded in `expected.json`.
void main() {
  final goldenDir = locateGoldenDir();

  test('golden fixtures are present', () {
    expect(goldenDir, isNotNull);
  });

  if (goldenDir == null) return;

  for (final scenario in goldenScenarios(goldenDir)) {
    final name = scenario.path.split(Platform.pathSeparator).last;
    test('punches match golden — $name', () {
      final input =
          jsonDecode(File('${scenario.path}/input.json').readAsStringSync())
              as Map<String, Object?>;
      final expected =
          jsonDecode(File('${scenario.path}/expected.json').readAsStringSync())
              as Map<String, Object?>;

      final sequence = PoseSequence.fromJson(input);
      final scale = computeBodyScale(sequence);
      final punches = PunchDetector().detect(sequence, scale);

      final got = punches
          .map((p) => <String, Object?>{
                'side': p.side.name,
                'startIndex': p.startIndex,
                'peakIndex': p.peakIndex,
                'endIndex': p.endIndex,
                'punchType': p.punchType.value,
              })
          .toList();
      final want = (expected['punches'] as List<Object?>)
          .map((e) => e as Map<String, Object?>)
          .map((e) => <String, Object?>{
                'side': e['side'],
                'startIndex': e['startIndex'],
                'peakIndex': e['peakIndex'],
                'endIndex': e['endIndex'],
                'punchType': e['punchType'],
              })
          .toList();

      expect(got, want);

      // Peak reach agrees numerically too (rounded to 6dp in the golden).
      for (var i = 0; i < punches.length; i++) {
        final wantReach =
            ((expected['punches'] as List<Object?>)[i] as Map<String, Object?>)['peakReach']
                as num;
        expect(punches[i].peakReach, closeTo(wantReach.toDouble(), 1e-6));
      }
    });
  }
}
