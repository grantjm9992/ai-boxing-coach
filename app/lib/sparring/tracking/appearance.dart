import 'dart:math' as math;

import 'package:sparring_pose/sparring_pose.dart' show kAppearanceBins;

/// Distances between the identity cues the tracker compares: colour
/// histograms (kit), limb-length ratios (body shape) and scale.

/// Distance used when two descriptors can't be compared (a region missing on
/// either side): neutral — neither evidence for nor against.
const double kNeutralAppearanceDistance = 0.35;

/// Distance between two appearance descriptors (torso + shorts histograms), in
/// 0..1: the total-variation distance per region, averaged over the regions
/// both sides saw. Shorts are weighted a little higher — tops get covered by
/// arms and gloves far more than shorts do.
double appearanceDistance(List<double> a, List<double> b) {
  var total = 0.0;
  var weight = 0.0;
  for (var region = 0; region < 2; region++) {
    final offset = region * kAppearanceBins;
    if (a.length < offset + kAppearanceBins || b.length < offset + kAppearanceBins) {
      continue;
    }
    var sumA = 0.0, sumB = 0.0;
    for (var k = 0; k < kAppearanceBins; k++) {
      sumA += a[offset + k];
      sumB += b[offset + k];
    }
    if (sumA <= 0.5 || sumB <= 0.5) continue; // region not seen
    var tv = 0.0;
    for (var k = 0; k < kAppearanceBins; k++) {
      tv += (a[offset + k] / sumA - b[offset + k] / sumB).abs();
    }
    final w = region == 0 ? 1.0 : 1.3;
    total += w * tv / 2;
    weight += w;
  }
  return weight == 0 ? kNeutralAppearanceDistance : total / weight;
}

/// Mean of descriptors, region by region, over the descriptors that saw that
/// region — so a frame with the shorts hidden doesn't dilute the shorts.
List<double> meanAppearance(Iterable<List<double>> descriptors) {
  final out = List<double>.filled(kAppearanceBins * 2, 0);
  for (var region = 0; region < 2; region++) {
    final offset = region * kAppearanceBins;
    var n = 0;
    for (final d in descriptors) {
      if (d.length < offset + kAppearanceBins) continue;
      var sum = 0.0;
      for (var k = 0; k < kAppearanceBins; k++) {
        sum += d[offset + k];
      }
      if (sum <= 0.5) continue;
      for (var k = 0; k < kAppearanceBins; k++) {
        out[offset + k] += d[offset + k] / sum;
      }
      n++;
    }
    if (n > 0) {
      for (var k = 0; k < kAppearanceBins; k++) {
        out[offset + k] /= n;
      }
    }
  }
  return out;
}

/// Relative distance between two shape vectors (limb / torso ratios): the
/// mean absolute log-ratio over the limbs both have. 0.0 identical, ~0.1 a
/// clearly different build; [double.nan] when nothing is comparable.
double shapeDistance(List<double> a, List<double> b) {
  var sum = 0.0;
  var n = 0;
  for (var i = 0; i < math.min(a.length, b.length); i++) {
    final x = a[i], y = b[i];
    if (!x.isFinite || !y.isFinite || x <= 0 || y <= 0) continue;
    sum += math.log(x / y).abs();
    n++;
  }
  return n == 0 ? double.nan : sum / n;
}

/// Element-wise median of shape vectors, ignoring NaN.
List<double> medianShape(Iterable<List<double>> shapes) {
  final columns = <List<double>>[];
  for (final s in shapes) {
    for (var i = 0; i < s.length; i++) {
      while (columns.length <= i) {
        columns.add(<double>[]);
      }
      if (s[i].isFinite) columns[i].add(s[i]);
    }
  }
  return <double>[for (final c in columns) median(c)];
}

/// Median of [values] (NaN when empty). Sorts a copy.
double median(List<double> values) {
  if (values.isEmpty) return double.nan;
  final sorted = List<double>.of(values)..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// A short colour name for one histogram's dominant bin — used to describe
/// the fighters to the AI coach ("black top, red shorts"). Bin 0 also covers
/// bare skin, so it's named cautiously.
String? dominantColourName(List<double> descriptor, {required bool shorts}) {
  const names = <String>[
    'red/orange (or bare skin)',
    'yellow',
    'green',
    'green',
    'cyan',
    'blue',
    'purple',
    'pink/red',
    'black',
    'grey',
    'white',
  ];
  final offset = shorts ? kAppearanceBins : 0;
  if (descriptor.length < offset + kAppearanceBins) return null;
  var best = -1;
  var bestValue = 0.0;
  var sum = 0.0;
  for (var k = 0; k < kAppearanceBins; k++) {
    final v = descriptor[offset + k];
    sum += v;
    if (v > bestValue) {
      bestValue = v;
      best = k;
    }
  }
  if (best < 0 || sum <= 0.5 || bestValue / sum < 0.3) return null;
  return names[best];
}
