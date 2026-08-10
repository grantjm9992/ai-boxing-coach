import 'dart:io';

/// Shared helpers for the cross-language golden tests. Not a `_test.dart` file,
/// so `flutter test` treats it as a library rather than a suite.

/// Walks up from the working directory to find `fixtures/golden`, so the tests
/// work whether run from the package dir or the repo root. Null if not found.
Directory? locateGoldenDir() {
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

/// The scenario directories under the golden dir that have an `input.json`,
/// sorted for stable test ordering.
List<Directory> goldenScenarios(Directory goldenDir) =>
    goldenDir
        .listSync()
        .whereType<Directory>()
        .where((d) => File('${d.path}/input.json').existsSync())
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
