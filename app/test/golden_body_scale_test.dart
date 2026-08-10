import 'dart:convert';
import 'dart:io';

import 'package:boxing_coach/analysis/features.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Dart half of the cross-language golden contract (see
/// `tests/test_golden_fixtures.py` for the Python half). Both suites read the
/// same `fixtures/golden/<name>/{input.json, expected.json}` files: this asserts
/// the ported engine derives the same numbers the reference engine did.
void main() {
  final goldenDir = _locateGoldenDir();

  test('golden fixtures are present', () {
    expect(
      goldenDir,
      isNotNull,
      reason: 'no fixtures/golden — run `python scripts/emit_golden_fixtures.py`',
    );
  });

  if (goldenDir == null) return;

  final scenarios = goldenDir
      .listSync()
      .whereType<Directory>()
      .where((d) => File('${d.path}/input.json').existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final scenario in scenarios) {
    final name = scenario.path.split(Platform.pathSeparator).last;
    test('body scale matches golden — $name', () {
      final input =
          jsonDecode(File('${scenario.path}/input.json').readAsStringSync())
              as Map<String, Object?>;
      final expected =
          jsonDecode(File('${scenario.path}/expected.json').readAsStringSync())
              as Map<String, Object?>;

      final sequence = PoseSequence.fromJson(input);
      final expectedScale = (expected['bodyScale'] as num).toDouble();

      expect(computeBodyScale(sequence), closeTo(expectedScale, 1e-9));
    });
  }
}

/// Walks up from the test's working directory to find `fixtures/golden`, so the
/// test works whether run from the package dir or the repo root.
Directory? _locateGoldenDir() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory('${dir.path}/fixtures/golden');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
