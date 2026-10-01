/// The two identities a sparring round is resolved into.
///
/// Labels are the tracker's: before the user has said which one they are, A
/// is simply whoever started on the left. Once they have (see
/// `SparringSession.identified`), every round is linked against their
/// appearance so that **A is always the user** and B their partner.
enum FighterLabel {
  a('a'),
  b('b');

  const FighterLabel(this.value);

  /// Wire value.
  final String value;

  FighterLabel get other => this == FighterLabel.a ? FighterLabel.b : FighterLabel.a;

  /// The letter shown before identification ("Fighter A").
  String get letter => value.toUpperCase();

  static FighterLabel? fromValue(Object? value) {
    for (final label in FighterLabel.values) {
      if (label.value == value) return label;
    }
    return null;
  }
}

/// A half-open range of frame positions `[start, end)` — where a fighter
/// couldn't be resolved, or the fighters overlapped.
class FrameRange {
  const FrameRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;

  bool contains(int position) => position >= start && position < end;

  bool overlaps(int from, int to) => from < end && to >= start;

  Map<String, Object?> toJson() => <String, Object?>{'s': start, 'e': end};

  factory FrameRange.fromJson(Map<String, Object?> json) =>
      FrameRange((json['s'] as num).toInt(), (json['e'] as num).toInt());

  /// Merges a sorted-or-not set of flags into ranges: every position where
  /// [flagged] is true, grouped into maximal runs.
  static List<FrameRange> fromFlags(List<bool> flagged) {
    final out = <FrameRange>[];
    int? open;
    for (var i = 0; i < flagged.length; i++) {
      if (flagged[i]) {
        open ??= i;
      } else if (open != null) {
        out.add(FrameRange(open, i));
        open = null;
      }
    }
    if (open != null) out.add(FrameRange(open, flagged.length));
    return out;
  }
}
