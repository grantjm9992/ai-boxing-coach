/// Body landmarks used by the analysis engine — the Dart mirror of
/// `src/boxing_coach/domain/landmarks.py`.
///
/// The integer values are the canonical MediaPipe Pose indices, so a
/// MediaPipe-backed estimator populates them directly with no remapping. This is
/// the shipping runtime; the Python engine remains the reference and the
/// calibration lab. The two are kept in step by the golden fixtures under
/// `fixtures/golden/`.
///
/// Coordinate convention (identical to the Python side):
///   - x increases to the right of the image
///   - y increases downward (so "higher up" means smaller y)
///   - z is an optional depth estimate; treated as unusable in v0.5
/// All coordinates are image-normalised to roughly [0, 1].
library;

enum Landmark {
  nose(0),
  leftEye(2),
  rightEye(5),
  leftEar(7),
  rightEar(8),
  leftShoulder(11),
  rightShoulder(12),
  leftElbow(13),
  rightElbow(14),
  leftWrist(15),
  rightWrist(16),
  leftHip(23),
  rightHip(24),
  leftKnee(25),
  rightKnee(26),
  leftAnkle(27),
  rightAnkle(28);

  const Landmark(this.mpIndex);

  /// The MediaPipe Pose landmark index — also the JSON key in the wire format.
  /// (Named to avoid the enum's built-in ordinal `index`.)
  final int mpIndex;

  static final Map<int, Landmark> _byIndex = <int, Landmark>{
    for (final l in Landmark.values) l.mpIndex: l,
  };

  /// The landmark for a MediaPipe index, or null if it is one we don't model.
  static Landmark? fromIndex(int index) => _byIndex[index];
}

/// Which side of the body a limb belongs to.
enum Side {
  left,
  right;

  Landmark get wrist => this == Side.left ? Landmark.leftWrist : Landmark.rightWrist;
  Landmark get shoulder =>
      this == Side.left ? Landmark.leftShoulder : Landmark.rightShoulder;
  Landmark get elbow => this == Side.left ? Landmark.leftElbow : Landmark.rightElbow;
  Landmark get hip => this == Side.left ? Landmark.leftHip : Landmark.rightHip;
  Landmark get ankle => this == Side.left ? Landmark.leftAnkle : Landmark.rightAnkle;
}

/// Boxing stance. Determines which hand is lead vs rear.
enum Stance {
  /// Left hand/foot forward → lead = left, rear = right.
  orthodox,

  /// Right hand/foot forward → lead = right, rear = left.
  southpaw;

  Side get lead => this == Stance.orthodox ? Side.left : Side.right;
  Side get rear => this == Stance.orthodox ? Side.right : Side.left;
}
