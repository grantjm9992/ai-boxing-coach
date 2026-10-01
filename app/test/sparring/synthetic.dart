import 'dart:math' as math;

import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/sparring/model/fighter.dart';
import 'package:boxing_coach/sparring/pose/multi_pose.dart';
import 'package:boxing_coach/sparring/tracking/fighter_tracker.dart';

/// Synthetic side-on sparring footage for tracker and analysis tests: stick
/// figures in profile with a kit (one-hot colour bins) and a build (limb
/// ratios), recorded with their true identity so tests can score the tracker.

/// Who each generated body really is, keyed on its keypoint map (the tracker
/// passes those maps through to the fighters' sequences unchanged).
final Expando<int> truth = Expando<int>('person');

/// A person's fixed look.
class Person {
  const Person(
    this.id, {
    this.topBin = 8,
    this.shortsBin = 0,
    this.upperArm = 0.6,
    this.forearm = 0.6,
    this.thigh = 0.8,
    this.shin = 0.8,
    this.scale = 0.18,
  });

  final int id;
  final int topBin;
  final int shortsBin;
  final double upperArm;
  final double forearm;
  final double thigh;
  final double shin;

  /// Torso length in image units.
  final double scale;
}

/// One body: [person] with hips at ([x], [y]) facing [facing] (+1 right).
/// [leadReach] / [rearReach] extend the lead / rear arm (0 guard, 1 full).
/// [stance] orthodox puts the left foot forward.
PoseCandidate body(
  Person person, {
  required double x,
  double y = 0.62,
  int facing = 1,
  double leadReach = 0,
  double rearReach = 0,
  Stance stance = Stance.orthodox,
  double visibility = 0.95,
  math.Random? jitter,
}) {
  final s = person.scale;
  double j() => jitter == null ? 0 : (jitter.nextDouble() - 0.5) * 0.004;
  Keypoint kp(double px, double py) => Keypoint(px + j(), py + j(), visibility: visibility);

  final f = facing.toDouble();
  final lead = stance.lead;
  final keypoints = <Landmark, Keypoint>{};

  // Hips and shoulders nearly overlap side-on.
  final hipL = <double>[x + 0.01 * f, y];
  final hipR = <double>[x - 0.01 * f, y];
  final shoulderY = y - s;
  final shL = <double>[x + 0.02 * f + 0.01 * f, shoulderY];
  final shR = <double>[x + 0.02 * f - 0.01 * f, shoulderY];
  keypoints[Landmark.leftHip] = kp(hipL[0], hipL[1]);
  keypoints[Landmark.rightHip] = kp(hipR[0], hipR[1]);
  keypoints[Landmark.leftShoulder] = kp(shL[0], shL[1]);
  keypoints[Landmark.rightShoulder] = kp(shR[0], shR[1]);

  // Arms: in guard the elbow hangs down and forward, the fist by the chin;
  // reaching swings the whole arm out level towards the opponent.
  void arm(Side side, List<double> shoulder, double reach) {
    final upper = person.upperArm * s;
    final fore = person.forearm * s;
    final guardElbow = <double>[shoulder[0] + 0.35 * upper * f, shoulder[1] + 0.94 * upper];
    final guardWrist = <double>[guardElbow[0] + 0.55 * fore * f, guardElbow[1] - 0.83 * fore];
    final outElbow = <double>[shoulder[0] + upper * f, shoulder[1]];
    final outWrist = <double>[outElbow[0] + fore * f, outElbow[1]];
    double lerp(double a, double b) => a + (b - a) * reach;
    final elbow = <double>[lerp(guardElbow[0], outElbow[0]), lerp(guardElbow[1], outElbow[1])];
    final wrist = <double>[lerp(guardWrist[0], outWrist[0]), lerp(guardWrist[1], outWrist[1])];
    keypoints[side.elbow] = kp(elbow[0], elbow[1]);
    keypoints[side.wrist] = kp(wrist[0], wrist[1]);
  }

  arm(lead, lead == Side.left ? shL : shR, leadReach);
  arm(stance.rear, stance.rear == Side.left ? shL : shR, rearReach);

  // Legs: lead foot forward, rear foot back.
  void leg(Side side, List<double> hip, double forward) {
    final thigh = person.thigh * s;
    final shin = person.shin * s;
    final knee = <double>[hip[0] + forward * 0.45 * thigh * f, hip[1] + 0.89 * thigh];
    final ankle = <double>[knee[0] + forward * 0.3 * shin * f, knee[1] + 0.95 * shin];
    keypoints[side.knee] = kp(knee[0], knee[1]);
    keypoints[side.ankle] = kp(ankle[0], ankle[1]);
  }

  leg(lead, lead == Side.left ? hipL : hipR, 1);
  leg(stance.rear, stance.rear == Side.left ? hipL : hipR, -1);

  // Head: ears over the shoulders, nose ahead of them.
  final headY = shoulderY - 0.35 * s;
  final earX = x + 0.02 * f;
  keypoints[Landmark.leftEar] = kp(earX + 0.005 * f, headY);
  keypoints[Landmark.rightEar] = kp(earX - 0.005 * f, headY);
  keypoints[Landmark.nose] = kp(earX + 0.22 * s * f, headY + 0.03 * s);
  keypoints[Landmark.leftEye] = kp(earX + 0.15 * s * f, headY - 0.03 * s);
  keypoints[Landmark.rightEye] = kp(earX + 0.14 * s * f, headY - 0.03 * s);

  final appearance = List<double>.filled(22, 0);
  appearance[person.topBin] = 1;
  appearance[11 + person.shortsBin] = 1;
  final candidate = PoseCandidate(keypoints: keypoints, appearance: appearance);
  truth[keypoints] = person.id;
  return candidate;
}

/// A round from per-frame bodies; candidate order is shuffled each frame (the
/// detector's order means nothing).
MultiPoseRound roundOf(
  List<List<PoseCandidate>> perFrame, {
  double fps = 20,
  int seed = 7,
}) {
  final random = math.Random(seed);
  return MultiPoseRound(
    fps: fps,
    frames: <MultiPoseFrame>[
      for (var i = 0; i < perFrame.length; i++)
        MultiPoseFrame(
          index: i,
          timestampMs: i * 1000 / fps,
          candidates: List<PoseCandidate>.of(perFrame[i])..shuffle(random),
        ),
    ],
  );
}

/// The true person behind [label]'s pose at [position], or null if unresolved.
int? personAt(TrackedRound round, FighterLabel label, int position) {
  final frame = round.fighters[label]!.frames[position];
  if (frame.keypoints.isEmpty) return null;
  return truth[frame.keypoints];
}

/// Identity score of [round] against ground truth: per fighter, which person
/// it mostly is, how many frames are that person, and how many are someone
/// else (the number that must be zero).
class IdentityScore {
  IdentityScore(this.person, this.correct, this.wrong, this.unresolved);
  final Map<FighterLabel, int?> person;
  final int correct;
  final int wrong;
  final int unresolved;

  double get accuracy => correct + wrong == 0 ? 0 : correct / (correct + wrong);
}

IdentityScore scoreIdentity(TrackedRound round) {
  final person = <FighterLabel, int?>{};
  var correct = 0, wrong = 0, unresolved = 0;
  for (final label in FighterLabel.values) {
    final counts = <int, int>{};
    for (var p = 0; p < round.frameCount; p++) {
      final who = personAt(round, label, p);
      if (who != null) counts[who] = (counts[who] ?? 0) + 1;
    }
    int? majority;
    var best = 0;
    counts.forEach((who, n) {
      if (n > best) {
        best = n;
        majority = who;
      }
    });
    person[label] = majority;
    for (var p = 0; p < round.frameCount; p++) {
      final who = personAt(round, label, p);
      if (who == null) {
        unresolved++;
      } else if (who == majority) {
        correct++;
      } else {
        wrong++;
      }
    }
  }
  return IdentityScore(person, correct, wrong, unresolved);
}

/// A plain single-person [PoseSequence] of [bodies] (for analysis tests).
PoseSequence sequenceOf(List<PoseCandidate?> bodies, {double fps = 20}) => PoseSequence(
  frames: <PoseFrame>[
    for (var i = 0; i < bodies.length; i++)
      PoseFrame(
        index: i,
        timestampMs: i * 1000 / fps,
        keypoints: bodies[i]?.keypoints ?? const <Landmark, Keypoint>{},
      ),
  ],
  fps: fps,
);
