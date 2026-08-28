// The labelled regression dataset (brief §26): known clips with their expected
// punches and issues, so combination-classification accuracy can be tracked as
// the algorithm changes. This is the data model + scoring; the clips + labels
// are collected over time.

/// One labelled clip.
class RegressionCase {
  const RegressionCase({
    required this.video,
    this.expectedPunches = const <int>[],
    this.knownIssues = const <String>[],
  });

  /// Clip identifier / filename.
  final String video;

  /// Expected punch numbers, e.g. `[1, 2, 3]`.
  final List<int> expectedPunches;

  /// Expected fault codes (taxonomy), e.g. `["GUARD_003"]`.
  final List<String> knownIssues;

  Map<String, Object?> toJson() => <String, Object?>{
    'video': video,
    'expected_punches': expectedPunches,
    'known_issues': knownIssues,
  };

  factory RegressionCase.fromJson(Map<String, Object?> json) => RegressionCase(
    video: json['video'] as String,
    expectedPunches: <int>[
      for (final n in (json['expected_punches'] as List<Object?>? ?? const []))
        (n as num).toInt(),
    ],
    knownIssues: <String>[
      for (final s in (json['known_issues'] as List<Object?>? ?? const []))
        s as String,
    ],
  );
}

/// A labelled dataset, loadable from / dumpable to a JSON list.
class RegressionDataset {
  const RegressionDataset(this.cases);

  final List<RegressionCase> cases;

  List<Object?> toJson() => cases.map((c) => c.toJson()).toList();

  factory RegressionDataset.fromJson(List<Object?> json) => RegressionDataset(
    <RegressionCase>[
      for (final c in json)
        RegressionCase.fromJson((c as Map).cast<String, Object?>()),
    ],
  );
}

bool _sameSequence(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Fraction of pairs whose detected sequence exactly matches the expected one —
/// the headline combination-classification accuracy (0 when empty).
double sequenceMatchAccuracy(
  Iterable<(List<int> expected, List<int> detected)> pairs,
) {
  final list = pairs.toList();
  if (list.isEmpty) return 0;
  final matched =
      list.where((p) => _sameSequence(p.$1, p.$2)).length;
  return matched / list.length;
}

/// Token-level accuracy: fraction of punch positions classified correctly,
/// aligned from the start, over the total expected punches (0 when empty).
/// A more forgiving measure than exact match for tuning.
double punchTokenAccuracy(
  Iterable<(List<int> expected, List<int> detected)> pairs,
) {
  var correct = 0;
  var total = 0;
  for (final (expected, detected) in pairs) {
    total += expected.length;
    final n = expected.length < detected.length
        ? expected.length
        : detected.length;
    for (var i = 0; i < n; i++) {
      if (expected[i] == detected[i]) correct++;
    }
  }
  return total == 0 ? 0 : correct / total;
}
