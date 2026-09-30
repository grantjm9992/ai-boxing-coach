import 'checkpoints.dart';
import 'combination.dart';
import 'features.dart';
import 'geometry.dart' as geo;
import 'landmarks.dart';
import 'pose.dart';
import 'punch.dart';

/// On-device grading of a drill's [TechniqueCheckpoint]s, punch by punch.
///
/// Every threshold is in torso-lengths (the body scale), so it holds across
/// people and camera distances. These are 2D, single-camera reads: each result
/// carries a confidence that says how much to trust it, and a checkpoint the
/// pose can't see is [CheckpointStatus.unmeasured] rather than guessed —
/// the AI review grades those from the video.

enum CheckpointStatus {
  passed('passed'),
  failed('failed'),
  unmeasured('unmeasured');

  const CheckpointStatus(this.value);
  final String value;

  static CheckpointStatus fromValue(String? value) => CheckpointStatus.values
      .firstWhere((s) => s.value == value, orElse: () => unmeasured);
}

/// One checkpoint graded on one punch.
class CheckpointResult {
  const CheckpointResult({
    required this.checkpointId,
    required this.punchNumber,
    required this.punchIndex,
    required this.status,
    required this.timestampMs,
    this.confidence = 0,
    this.metrics = const <String, double>{},
  });

  final String checkpointId;
  final int punchNumber;

  /// Index into the round's punch list.
  final int punchIndex;
  final CheckpointStatus status;

  /// The punch's peak — where the frames that show it are.
  final double timestampMs;
  final double confidence;
  final Map<String, double> metrics;

  bool get failed => status == CheckpointStatus.failed;
  bool get passed => status == CheckpointStatus.passed;

  Map<String, Object?> toJson() => <String, Object?>{
    'checkpointId': checkpointId,
    'punchNumber': punchNumber,
    'punchIndex': punchIndex,
    'status': status.value,
    'timestampMs': timestampMs,
    'confidence': confidence,
    'metrics': metrics,
  };

  factory CheckpointResult.fromJson(Map<String, Object?> json) =>
      CheckpointResult(
        checkpointId: json['checkpointId'] as String? ?? '',
        punchNumber: (json['punchNumber'] as num?)?.toInt() ?? 0,
        punchIndex: (json['punchIndex'] as num?)?.toInt() ?? -1,
        status: CheckpointStatus.fromValue(json['status'] as String?),
        timestampMs: (json['timestampMs'] as num?)?.toDouble() ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        metrics: <String, double>{
          for (final e
              in (json['metrics'] as Map<String, Object?>? ?? const {}).entries)
            e.key: (e.value as num).toDouble(),
        },
      );
}

/// How one checkpoint went across the round: the reps that passed, failed or
/// couldn't be read, and where the first clear failure was.
class CheckpointTally {
  const CheckpointTally({
    required this.checkpoint,
    this.passed = 0,
    this.failed = 0,
    this.unmeasured = 0,
    this.firstFailureMs,
    this.confidence = 0,
  });

  final DrillCheckpoint checkpoint;
  final int passed;
  final int failed;
  final int unmeasured;
  final double? firstFailureMs;

  /// Mean confidence of the graded reps.
  final double confidence;

  int get graded => passed + failed;

  /// Share of graded reps that passed; null when none could be graded.
  double? get passRate => graded == 0 ? null : passed / graded;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': checkpoint.id,
    'punchNumber': checkpoint.punchNumber,
    'passed': passed,
    'failed': failed,
    'unmeasured': unmeasured,
    'firstFailureMs': firstFailureMs,
    'confidence': confidence,
  };

  /// Null when the id is no longer in the catalogue.
  static CheckpointTally? fromJson(Map<String, Object?> json) {
    final id = json['id'] as String?;
    final number = (json['punchNumber'] as num?)?.toInt();
    if (id == null || number == null) return null;
    final checkpoint = Checkpoints.forPunch(number)
        .where((c) => c.id == id)
        .firstOrNull;
    if (checkpoint == null) return null;
    return CheckpointTally(
      checkpoint: DrillCheckpoint(
        checkpoint: checkpoint,
        punchNumber: number,
        punchName: Checkpoints.punchLabel(number),
      ),
      passed: (json['passed'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      unmeasured: (json['unmeasured'] as num?)?.toInt() ?? 0,
      firstFailureMs: (json['firstFailureMs'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Thresholds for the checkpoint measures, in torso-lengths unless noted.
/// Starting points to calibrate against coach-labelled drills, like every other
/// threshold in the engine.
class CheckpointConfig {
  const CheckpointConfig({
    this.snapBackMaxRatio = 1.5,
    this.snapBackGraceMs = 80,
    this.minShoulderDrive = 0.12,
    this.minStraightReachForRotation = 0.9,
    this.maxBelowShoulder = 0.2,
    this.guardMaxFromNose = 0.55,
    this.guardDropBelowShoulder = 0.35,
    this.hookMaxBelowShoulder = 0.25,
    this.hookMaxElbowAboveWrist = 0.3,
    this.hookMinElbowDeg = 65,
    this.hookMaxElbowDeg = 125,
  });

  /// The jab fails when it takes longer than this × its extension time to come
  /// back (and more than [snapBackGraceMs] longer).
  final double snapBackMaxRatio;
  final double snapBackGraceMs;

  /// Rotation fails below this shoulder travel relative to the hips.
  final double minShoulderDrive;

  /// Short straights don't show rotation reliably — below this reach the
  /// rotation checkpoint is unmeasured rather than failed.
  final double minStraightReachForRotation;

  /// A head-level punch fails when the wrist lands this far below the shoulder.
  final double maxBelowShoulder;

  /// The guard hand counts as "at the face" within this distance of the nose.
  final double guardMaxFromNose;

  /// Fallback when the nose isn't tracked: the guard hand fails this far below
  /// its shoulder.
  final double guardDropBelowShoulder;

  /// A hook fails when the fist lands this far below the shoulder…
  final double hookMaxBelowShoulder;

  /// …or when the elbow sits this far above the fist (a downward chop).
  final double hookMaxElbowAboveWrist;

  /// The hook's elbow angle passes inside this band (degrees). Wide on purpose:
  /// a single camera foreshortens the arm.
  final double hookMinElbowDeg;
  final double hookMaxElbowDeg;
}

/// How much each measure can be trusted from a single 2D camera.
const Map<CheckpointCheck, double> _confidence = <CheckpointCheck, double>{
  CheckpointCheck.snapBack: 0.7,
  CheckpointCheck.rotation: 0.55,
  CheckpointCheck.punchAtShoulderHeight: 0.65,
  CheckpointCheck.guardHandAtFace: 0.7,
  CheckpointCheck.hookLevel: 0.6,
  CheckpointCheck.hookArmAngle: 0.55,
};

/// Grades [checkpoints] on every punch in [punches] whose number they cover.
/// Punches that can't be numbered (unknown type) are skipped.
List<CheckpointResult> evaluateCheckpoints(
  PoseSequence sequence,
  List<PunchEvent> punches,
  Stance stance,
  double bodyScale,
  List<DrillCheckpoint> checkpoints, {
  CheckpointConfig config = const CheckpointConfig(),
  PunchNumbering numbering = const PunchNumbering(),
}) {
  if (checkpoints.isEmpty || punches.isEmpty || bodyScale <= 0) {
    return const <CheckpointResult>[];
  }
  final results = <CheckpointResult>[];
  for (var i = 0; i < punches.length; i++) {
    final punch = punches[i];
    final number =
        numbering.numberFor(punch.punchType, isLead: punch.side == stance.lead);
    if (number == null) continue;
    for (final dc in checkpoints) {
      if (dc.punchNumber != number) continue;
      results.add(_grade(
        sequence,
        punch,
        i,
        number,
        dc.checkpoint,
        bodyScale,
        config,
      ));
    }
  }
  return results;
}

/// Rolls [results] up per checkpoint, in the drill's checkpoint order.
List<CheckpointTally> tallyCheckpoints(
  List<DrillCheckpoint> checkpoints,
  List<CheckpointResult> results,
) {
  return <CheckpointTally>[
    for (final dc in checkpoints) _tally(dc, results),
  ];
}

CheckpointTally _tally(DrillCheckpoint dc, List<CheckpointResult> results) {
  var passed = 0;
  var failed = 0;
  var unmeasured = 0;
  double? firstFailure;
  var confidenceSum = 0.0;
  for (final r in results) {
    if (r.checkpointId != dc.id) continue;
    switch (r.status) {
      case CheckpointStatus.passed:
        passed++;
        confidenceSum += r.confidence;
      case CheckpointStatus.failed:
        failed++;
        confidenceSum += r.confidence;
        if (firstFailure == null || r.timestampMs < firstFailure) {
          firstFailure = r.timestampMs;
        }
      case CheckpointStatus.unmeasured:
        unmeasured++;
    }
  }
  final graded = passed + failed;
  return CheckpointTally(
    checkpoint: dc,
    passed: passed,
    failed: failed,
    unmeasured: unmeasured,
    firstFailureMs: firstFailure,
    confidence: graded == 0 ? 0 : confidenceSum / graded,
  );
}

CheckpointResult _grade(
  PoseSequence sequence,
  PunchEvent punch,
  int punchIndex,
  int number,
  TechniqueCheckpoint checkpoint,
  double scale,
  CheckpointConfig cfg,
) {
  final peak = sequence.frames[punch.peakIndex];
  final metrics = <String, double>{};

  CheckpointResult result(CheckpointStatus status) => CheckpointResult(
    checkpointId: checkpoint.id,
    punchNumber: number,
    punchIndex: punchIndex,
    status: status,
    timestampMs: peak.timestampMs,
    confidence: status == CheckpointStatus.unmeasured
        ? 0
        : _confidence[checkpoint.check] ?? 0.5,
    metrics: metrics,
  );
  CheckpointResult verdict(bool ok) =>
      result(ok ? CheckpointStatus.passed : CheckpointStatus.failed);
  final unmeasured = result(CheckpointStatus.unmeasured);
  bool missing(List<double> p) => p.any((v) => v.isNaN);

  switch (checkpoint.check) {
    case CheckpointCheck.snapBack:
      {
        final start = sequence.frames[punch.startIndex].timestampMs;
        final end = sequence.frames[punch.endIndex].timestampMs;
        final out = peak.timestampMs - start;
        final back = end - peak.timestampMs;
        if (out <= 0 || back <= 0) return unmeasured;
        metrics['extend_ms'] = out;
        metrics['retract_ms'] = back;
        metrics['retract_ratio'] = back / out;
        final slow = back > out * cfg.snapBackMaxRatio &&
            back - out > cfg.snapBackGraceMs;
        return verdict(!slow);
      }
    case CheckpointCheck.rotation:
      {
        if (punch.punchType == PunchType.straight &&
            punch.peakReach < cfg.minStraightReachForRotation) {
          return unmeasured;
        }
        final drive = geo.shoulderDrive(
          sequence,
          punch.side,
          punch.startIndex,
          punch.peakIndex,
          scale,
        );
        if (drive == null) return unmeasured;
        metrics['shoulder_drive'] = drive;
        return verdict(drive >= cfg.minShoulderDrive);
      }
    case CheckpointCheck.punchAtShoulderHeight:
      {
        final wrist = geo.framePoint(peak, punch.side.wrist);
        final shoulder = geo.framePoint(peak, punch.side.shoulder);
        if (missing(wrist) || missing(shoulder)) return unmeasured;
        // Image y grows downward: positive = the fist is below the shoulder.
        final below = (wrist[1] - shoulder[1]) / scale;
        metrics['wrist_below_shoulder'] = below;
        return verdict(below <= cfg.maxBelowShoulder);
      }
    case CheckpointCheck.guardHandAtFace:
      {
        final other = punch.side == Side.left ? Side.right : Side.left;
        final wrist = geo.framePoint(peak, other.wrist);
        if (missing(wrist)) return unmeasured;
        final nose = geo.framePoint(peak, Landmark.nose);
        if (!missing(nose)) {
          final fromNose = geo.distance(wrist, nose) / scale;
          metrics['guard_from_nose'] = fromNose;
          return verdict(fromNose <= cfg.guardMaxFromNose);
        }
        final shoulder = geo.framePoint(peak, other.shoulder);
        if (missing(shoulder)) return unmeasured;
        final drop = (wrist[1] - shoulder[1]) / scale;
        metrics['guard_below_shoulder'] = drop;
        return verdict(drop <= cfg.guardDropBelowShoulder);
      }
    case CheckpointCheck.hookLevel:
      {
        final wrist = geo.framePoint(peak, punch.side.wrist);
        final shoulder = geo.framePoint(peak, punch.side.shoulder);
        final elbow = geo.framePoint(peak, punch.side.elbow);
        if (missing(wrist) || missing(shoulder)) return unmeasured;
        final below = (wrist[1] - shoulder[1]) / scale;
        metrics['wrist_below_shoulder'] = below;
        var chopping = false;
        if (!missing(elbow)) {
          // Positive = the elbow is above the fist: the arm is driving down.
          final elbowAbove = (wrist[1] - elbow[1]) / scale;
          metrics['elbow_above_wrist'] = elbowAbove;
          chopping = elbowAbove > cfg.hookMaxElbowAboveWrist;
        }
        return verdict(below <= cfg.hookMaxBelowShoulder && !chopping);
      }
    case CheckpointCheck.hookArmAngle:
      {
        final angle = geo.angleDeg(
          geo.framePoint(peak, punch.side.shoulder),
          geo.framePoint(peak, punch.side.elbow),
          geo.framePoint(peak, punch.side.wrist),
        );
        if (angle.isNaN) return unmeasured;
        metrics['elbow_deg'] = angle;
        return verdict(
          angle >= cfg.hookMinElbowDeg && angle <= cfg.hookMaxElbowDeg,
        );
      }
    case CheckpointCheck.videoOnly:
      {
        return unmeasured;
      }
  }
}
