import '../pose/multi_pose.dart';
import 'appearance.dart';

/// A run of one body through consecutive frames, linked only while that was
/// unambiguous. The tracker's unit of identity: a round becomes a few dozen
/// tracklets, and each is then labelled fighter A, B or neither.
class Tracklet {
  Tracklet(this.id);

  /// Stable within a round for a given input (ids are assigned in creation
  /// order), so identity decisions can be stored against it.
  final int id;

  /// Frame positions (indices into the round's frame list), ascending.
  final List<int> positions = <int>[];

  /// The body at each of [positions].
  final List<PoseCandidate> members = <PoseCandidate>[];

  int get start => positions.first;
  int get end => positions.last;
  int get length => positions.length;

  void add(int position, PoseCandidate candidate) {
    positions.add(position);
    members.add(candidate);
  }

  /// The body at [position], or null when this tracklet has none there.
  PoseCandidate? at(int position) {
    if (positions.isEmpty || position < start || position > end) return null;
    // Positions are ascending: binary search.
    var lo = 0, hi = positions.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final p = positions[mid];
      if (p == position) return members[mid];
      if (p < position) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return null;
  }

  /// True if this tracklet and [other] span overlapping frames.
  bool overlapsInTime(Tracklet other) => start <= other.end && other.start <= end;

  // Summary features — read only once the tracklet is finished.

  late final List<double> appearance =
      meanAppearance(members.map((m) => m.appearance));

  late final List<double> shape = medianShape(members.map((m) => m.shape));

  /// Median torso length (image units).
  late final double scale =
      median(<double>[for (final m in members) if (m.torso > 0) m.torso]);

  /// Median hip x — where in the frame this tracklet mostly was.
  late final double meanX =
      median(<double>[for (final m in members) if (m.hip != null) m.hip![0]]);

  List<double>? get startHip {
    for (final m in members) {
      if (m.hip != null) return m.hip;
    }
    return null;
  }

  List<double>? get endHip {
    for (final m in members.reversed) {
      if (m.hip != null) return m.hip;
    }
    return null;
  }
}
