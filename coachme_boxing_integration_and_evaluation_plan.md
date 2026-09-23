# AI Boxing Coach — CoachMe Integration & Evaluation Plan

## 1. Objective

Use the CoachMe boxing dataset as independent ground truth for the analysis engine.

CoachMe does **not** include raw video. It provides processed 3D pose/skeleton sequences in `.pkl` files using a 22-joint SMPL skeleton, plus coaching/error notes.

Therefore CoachMe can validate:

```text
3D Pose
→ Feature Extraction
→ Error Detection
→ Coaching Interpretation
```

It cannot validate:

```text
Raw Video
→ Pose Estimation
```

That first stage must be tested with our own raw-video benchmark.

The key principle is:

> Compare our detector output against independent coach-labelled ground truth. Do not let the same model simply grade its own analysis.

---

## 2. CoachMe SMPL Joint Mapping

```text
 0 : pelvis
 1 : left-hip
 2 : right-hip
 3 : spine-1
 4 : left-knee
 5 : right-knee
 6 : spine-2
 7 : left-ankle
 8 : right-ankle
 9 : spine-3
10 : left-foot
11 : right-foot
12 : neck
13 : left-collar
14 : right-collar
15 : head
16 : left-shoulder
17 : right-shoulder
18 : left-elbow
19 : right-elbow
20 : left-wrist
21 : right-wrist
```

Map these immediately into an internal provider-agnostic representation.

---

## 3. Internal Pose Schema

```ts
type Vec3 = {
  x: number;
  y: number;
  z: number;
};

type JointConfidence = {
  position: Vec3;
  confidence: number;
};

type BoxingPoseFrame = {
  frameIndex: number;
  timestampMs: number;

  joints: {
    pelvis: JointConfidence;

    leftHip: JointConfidence;
    rightHip: JointConfidence;

    leftKnee: JointConfidence;
    rightKnee: JointConfidence;

    leftAnkle: JointConfidence;
    rightAnkle: JointConfidence;

    leftFoot: JointConfidence;
    rightFoot: JointConfidence;

    spineLower: JointConfidence;
    spineMid: JointConfidence;
    spineUpper: JointConfidence;

    neck: JointConfidence;
    head: JointConfidence;

    leftShoulder: JointConfidence;
    rightShoulder: JointConfidence;

    leftElbow: JointConfidence;
    rightElbow: JointConfidence;

    leftWrist: JointConfidence;
    rightWrist: JointConfidence;

    leftCollar?: JointConfidence;
    rightCollar?: JointConfidence;
  };

  metadata: {
    source: "COACHME_SMPL" | "MEDIAPIPE" | "RTMPOSE" | "MULTICAM";
    stance?: "ORTHODOX" | "SOUTHPAW" | "UNKNOWN";
    cameraView?: string;
  };
};

type BoxingPoseSequence = {
  fps: number;
  frames: BoxingPoseFrame[];
  sourceId: string;
  motionType?: "JAB" | "CROSS" | "UNKNOWN";
};
```

No downstream code should rely on raw SMPL indices.

---

## 4. Normalisation Layer

All pose sources should pass through the same normalisation step.

### Translation

Use the pelvis as a body-relative origin:

```text
joint_normalized = joint - pelvis
```

Keep both:

```text
bodyRelativePose
globalPose
```

Global coordinates are still needed for movement and footwork.

### Scale

Use a stable body measurement such as median shoulder width:

```text
shoulderWidth = distance(leftShoulder, rightShoulder)
normalizedPosition = position / medianShoulderWidth
```

### Orientation

Create body-local axes:

```text
X = left ↔ right
Y = down ↔ up
Z = back ↔ forward
```

Derive them using shoulders and hips rather than assuming source X/Y/Z has a specific meaning.

---

## 5. Core Geometry Helpers

Implement reusable functions:

```text
distance(a, b)
angle(a, b, c)
dot(a, b)
cross(a, b)
normalize(v)
velocity(p1, p2, dt)
acceleration(v1, v2, dt)
```

Joint angle at B:

```text
A ----- B ----- C

v1 = A - B
v2 = C - B

angle = acos(dot(v1, v2) / (|v1| × |v2|))
```

---

## 6. Boxing Feature Extraction

### Guard

Use wrists, head, shoulders and neck.

Metrics:

```text
hand_to_head_distance
hand_height
guard_distance_change
guard_recovery_time
```

Example:

```text
lead hand at punch start
vs
lead hand at peak extension
```

Potential detector:

```text
IF distance_to_head increases materially
AND hand height drops
THEN LEAD_HAND_DROPS_DURING_CROSS
```

### Elbow / Extension

Use:

```text
shoulder → elbow → wrist
```

Derive:

```text
elbow_angle
arm_extension_ratio
peak_extension
retraction
```

### Shoulder Rotation

Track shoulder-line orientation:

```text
leftShoulder → rightShoulder
```

Store:

```text
start_rotation
peak_rotation
recovery_rotation
rotation_delta
```

### Hip Rotation

Track:

```text
leftHip → rightHip
```

Store:

```text
hip_rotation_delta
```

Later compare hip and shoulder timing.

### Shoulder–Hip Separation

```text
separation = shoulderRotation - hipRotation
```

Useful for kinetic-sequence analysis.

### Torso Lean

Use:

```text
pelvis → neck
```

or:

```text
pelvis → spineUpper
```

Store:

```text
forward_lean_deg
lateral_lean_deg
```

Track at start, peak and recovery.

### Head Position

Use:

```text
head - pelvis
```

Store:

```text
head_forward_offset
head_lateral_offset
```

### Stance Width

Use ankle/foot positions:

```text
stanceWidth = lateralDistance(leftAnkle, rightAnkle)
stanceWidthNormalized = stanceWidth / shoulderWidth
```

Prefer relative changes over arbitrary fixed thresholds.

### Front/Back Separation

Use body-local forward axis:

```text
depthDifference = leadFoot.z - rearFoot.z
```

### Foot Crossing

Track relative lateral positions of lead and rear foot.

### Lower-Body Participation

Use:

```text
hip rotation
pelvis translation
rear ankle/foot movement
knee movement
```

Possible heuristic:

```text
wrist speed high
+ shoulder rotation present
+ hip/lower-body motion minimal
→ INSUFFICIENT_LOWER_BODY_PARTICIPATION
```

### Rear Foot / Heel Proxy

No heel joint exists. Use ankle-foot vector as a proxy:

```text
rearFootVector = rearFoot - rearAnkle
```

Track orientation and vertical movement.

Do not present this as direct heel tracking.

---

## 7. Punch Event Detection

For each wrist calculate:

```text
velocity
acceleration
distance from shoulder
forward displacement
```

Typical punch event:

```text
wrist forward velocity rises
→ extension increases
→ velocity peaks
→ extension peaks
→ wrist retracts
```

Suggested model:

```ts
type PunchEvent = {
  hand: "LEFT" | "RIGHT";
  startFrame: number;
  peakFrame: number;
  endFrame: number;
  confidence: number;
};
```

CoachMe currently gives Jab/Cross, but keep the architecture generic.

---

## 8. Sequence-Level Feature Object

Do not analyse only isolated frames.

Example per-punch output:

```json
{
  "punch_type": "CROSS",
  "start_ms": 820,
  "peak_ms": 1080,
  "end_ms": 1410,

  "guard": {
    "lead_hand_drop": 0.22,
    "rear_hand_recovery_ms": 330
  },

  "rotation": {
    "shoulder_delta_deg": 41,
    "hip_delta_deg": 29,
    "shoulder_hip_separation_deg": 12
  },

  "body": {
    "forward_lean_peak_deg": 11,
    "head_forward_delta": 0.17
  },

  "stance": {
    "start_width": 1.08,
    "end_width": 0.96
  },

  "punch": {
    "peak_extension_ratio": 0.94
  }
}
```

This becomes the evidence consumed by the detector and coaching layer.

---

## 9. Error Detector Architecture

Use modular analyzers:

```text
GuardAnalyzer
RotationAnalyzer
LeanAnalyzer
HeadPositionAnalyzer
StanceAnalyzer
FootworkAnalyzer
BalanceAnalyzer
PunchMechanicsAnalyzer
```

Common output:

```ts
type Detection = {
  code: string;
  category: string;
  present: boolean;
  confidence: number;
  severity?: "LOW" | "MEDIUM" | "HIGH";
  evidence: Record<string, number>;
  frameRange?: {
    start: number;
    end: number;
  };
};
```

Example:

```json
{
  "code": "LEAD_HAND_DROPS_DURING_CROSS",
  "category": "GUARD",
  "present": true,
  "confidence": 0.91,
  "severity": "MEDIUM",
  "evidence": {
    "start_distance_to_head": 0.19,
    "peak_distance_to_head": 0.48,
    "distance_change": 0.29
  }
}
```

---

## 10. Initial Error Taxonomy

Start small and measurable.

```text
GUARD
- LEAD_HAND_LOW
- REAR_HAND_LOW
- HAND_NOT_RETURNING
- LEAD_HAND_DROPS_DURING_CROSS

ROTATION
- INSUFFICIENT_SHOULDER_ROTATION
- INSUFFICIENT_HIP_ROTATION
- POOR_SHOULDER_HIP_SEQUENCE

BODY_POSITION
- EXCESSIVE_FORWARD_LEAN
- EXCESSIVE_BACKWARD_LEAN
- HEAD_TOO_FAR_FORWARD

STANCE
- STANCE_TOO_NARROW
- STANCE_TOO_WIDE
- STANCE_NOT_RECOVERED
- FEET_CROSSING

BALANCE
- OFF_BALANCE_AFTER_PUNCH

PUNCH_MECHANICS
- OVEREXTENSION
- POOR_ELBOW_POSITION
- POOR_HAND_RECOVERY
- INSUFFICIENT_LOWER_BODY_PARTICIPATION
```

Do not expand aggressively until the benchmark loop works.

---

## 11. Map CoachMe Notes Into the Taxonomy

Always preserve original text.

Example:

```json
{
  "source": "COACHME",
  "source_annotation": "The rear hand is not protecting the chin.",
  "mapped_codes": ["REAR_HAND_LOW"],
  "mapping_confidence": 0.98
}
```

Examples:

```text
"Rear hand is not protecting the chin"
→ REAR_HAND_LOW

"More body rotation should be added"
→ INSUFFICIENT_ROTATION

"Head should not move forward"
→ HEAD_TOO_FAR_FORWARD

"Feet should be shoulder-width apart"
→ STANCE_WIDTH_ERROR

"Lower body is not participating"
→ INSUFFICIENT_LOWER_BODY_PARTICIPATION
```

An AI model may propose mappings, but initial mappings should be human-reviewed and then frozen for benchmark use.

---

## 12. Important: CoachMe Notes May Not Be Exhaustive

Do not assume:

```text
not mentioned = false
```

Use three states:

```text
PRESENT
ABSENT
UNKNOWN / NOT_ANNOTATED
```

Only score issues that are explicitly present or explicitly absent.

Ignore unknown categories for that example.

This prevents a valid detector output from being counted as a false positive simply because the coach did not mention it.

---

## 13. Detector vs CoachMe Ground Truth

This is the core evaluation loop.

```text
CoachMe Pose Sequence
→ Error Detector
→ Predicted Issues
```

Separately:

```text
CoachMe Coach Notes
→ Taxonomy Mapping
→ Ground-Truth Issues
```

Then:

```text
Predicted Issues
vs
Ground Truth
→ Evaluation Metrics
```

Example:

```text
EXPECTED:
REAR_HAND_LOW
INSUFFICIENT_ROTATION

DETECTED:
REAR_HAND_LOW
EXCESSIVE_FORWARD_LEAN
```

Result:

```text
REAR_HAND_LOW              = TP
INSUFFICIENT_ROTATION      = FN
EXCESSIVE_FORWARD_LEAN     = FP
```

---

## 14. Evaluation Metrics

Track:

```text
Precision
Recall
F1
False positives
False negatives
Per-category scores
```

Formulas:

```text
Precision = TP / (TP + FP)
Recall    = TP / (TP + FN)
F1        = 2 × Precision × Recall / (Precision + Recall)
```

Also track later:

```text
unsupported-claim rate
severity accuracy
confidence calibration
repeat-run consistency
```

---

## 15. This Is Not Circular Self-Grading

Correct:

```text
1. DETECTOR
What did our system predict?

2. GROUND TRUTH
What did independent coaches say?

3. EVALUATOR
How well did predictions match the coach labels?
```

Incorrect:

```text
our model predicts something
→ same model judges itself
→ declares itself correct
```

CoachMe should act as independent ground truth.

---

## 16. AI-Assisted Optimisation

AI can help with:

```text
mapping free-text notes
analysing false negatives
analysing false positives
proposing one targeted detector change
```

Example task:

```text
Current rotation recall: 0.61
Current rotation precision: 0.92

Review the false-negative examples.

Propose ONE change intended to improve recall
without reducing precision below 0.85.
```

Then:

```text
AI proposes change
→ candidate implementation
→ full benchmark
→ benchmark decides if better
```

The AI does not decide promotion.

---

## 17. Thresholds Must Be Empirical

Do not immediately define arbitrary rules such as:

```text
forward lean > 15° = bad
```

Inspect distributions.

Example:

```text
GOOD CROSSES
4°, 7°, 6°, 9°, 5°

COACH-LABELLED BAD CROSSES
13°, 17°, 21°, 15°
```

Then choose or learn thresholds from evidence.

Eventually a small classifier may replace a hand-coded threshold if it benchmarks better.

---

## 18. Build Good-Technique Baselines

For Jab and Cross build reference distributions for:

```text
shoulder rotation
hip rotation
lean
stance-width change
guard movement
extension ratio
recovery time
```

Compare future examples against validated ranges rather than arbitrary textbook constants.

---

## 19. Maintain Two Benchmark Datasets

### A. CoachMe Pose Benchmark

Purpose:

```text
feature extraction
error detection
coaching logic
```

Contains:

```text
3D skeletons
Jab/Cross
coach notes
```

Test:

```text
pose
→ features
→ detector
→ compare with coach notes
```

### B. Own Raw-Video Benchmark

Purpose:

```text
camera quality
pose-estimation quality
end-to-end validation
```

Contains:

```text
raw video
manual labels
deliberate errors
eventually coach-reviewed labels
```

Test:

```text
video
→ pose estimator
→ normalized pose
→ features
→ detector
→ compare with labels
```

Suggested first clips:

```text
good jab
jab with dropped rear hand
jab with forward lean
cross with poor rotation
cross with good rotation
cross with poor lower-body participation
1-2 with poor recovery
1-2-3 correct
1-3-4 correct
feet crossing
stance too narrow
stance not recovered
```

---

## 20. Provider-Agnostic Pipeline

CoachMe:

```text
CoachMe .pkl
↓
SMPL22Adapter
↓
CoordinateNormalizer
↓
BoxingPoseSequence
↓
PunchSegmenter
↓
FeatureExtractor
↓
TechniqueAnalyzers
↓
DetectedIssues
↓
BenchmarkComparator
↓
Metrics
```

Current app:

```text
Video
↓
MediaPipe / RTMPose
↓
PoseAdapter
↓
CoordinateNormalizer
↓
BoxingPoseSequence
↓
SAME PIPELINE
```

Future hardware:

```text
2–4 Cameras
↓
3D Reconstruction
↓
MultiCameraAdapter
↓
BoxingPoseSequence
↓
SAME PIPELINE
```

The hardware should improve the quality of the pose sequence, not require the boxing logic to be rewritten.

---

## 21. Where Qwen / Coaching AI Fits

Preferred architecture:

```text
POSE / VIDEO
↓
FEATURES
↓
DETECTIONS
↓
STRUCTURED EVIDENCE
↓
QWEN / COACHING AI
↓
USER-FACING COACHING
```

Do not rely on:

```text
VIDEO
→ QWEN
→ HOPE
```

Example evidence to Qwen:

```json
{
  "detected_issue": "LEAD_HAND_DROPS_DURING_CROSS",
  "confidence": 0.91,
  "evidence": {
    "start_distance_to_head": 0.19,
    "peak_distance_to_head": 0.48
  }
}
```

Qwen can then generate:

```text
why it matters
correction
drill recommendation
priority
```

---

## 22. Coding Agent Implementation Order

### Phase 1 — Pose Foundation

- [ ] `BoxingPoseFrame`
- [ ] `BoxingPoseSequence`
- [ ] `SMPL22Adapter`
- [ ] coordinate normalization
- [ ] body-relative coordinates
- [ ] global coordinates
- [ ] body-local axes
- [ ] vector/math helpers

### Phase 2 — Punch Segmentation

- [ ] wrist velocity
- [ ] wrist acceleration
- [ ] arm extension
- [ ] punch start
- [ ] punch peak
- [ ] punch end
- [ ] Jab/Cross segmentation

### Phase 3 — Feature Extraction

- [ ] hand-to-head distance
- [ ] hand height
- [ ] elbow angle
- [ ] extension ratio
- [ ] shoulder rotation
- [ ] hip rotation
- [ ] shoulder/hip separation
- [ ] torso lean
- [ ] head displacement
- [ ] stance width
- [ ] front/back foot separation
- [ ] wrist velocity
- [ ] guard recovery time
- [ ] lower-body movement metrics

### Phase 4 — CoachMe Integration

- [ ] load `.pkl`
- [ ] extract pose sequences
- [ ] extract coach notes
- [ ] preserve original annotation
- [ ] map notes into taxonomy
- [ ] support `PRESENT / ABSENT / UNKNOWN`
- [ ] manually review mappings

### Phase 5 — Initial Detectors

- [ ] `REAR_HAND_LOW`
- [ ] `LEAD_HAND_LOW`
- [ ] `LEAD_HAND_DROPS_DURING_CROSS`
- [ ] `INSUFFICIENT_SHOULDER_ROTATION`
- [ ] `INSUFFICIENT_HIP_ROTATION`
- [ ] `EXCESSIVE_FORWARD_LEAN`
- [ ] `HEAD_TOO_FAR_FORWARD`
- [ ] `STANCE_WIDTH_ERROR`
- [ ] `POOR_HAND_RECOVERY`
- [ ] `INSUFFICIENT_LOWER_BODY_PARTICIPATION`

### Phase 6 — Benchmark Runner

Implement:

```bash
evaluate-analysis
```

For each sample:

```text
load pose
load ground truth
run detector
compare predictions
store result
```

Output:

```text
overall precision
overall recall
overall F1

per-category precision
per-category recall
per-category F1

false positives
false negatives
ignored / unknown labels
```

### Phase 7 — Improvement Loop

```text
identify weak category
→ inspect failed examples
→ propose one change
→ run full benchmark
→ compare baseline/candidate
→ keep only if better
```

---

## 23. Guardrails

Do not:

- treat every unmentioned CoachMe issue as absent,
- let AI grade itself without coach ground truth,
- hard-code arbitrary biomechanics thresholds without evidence,
- couple analysis directly to SMPL,
- mix pose-estimation failures with boxing-reasoning failures,
- build dozens of detectors before evaluation works,
- discard original CoachMe annotation text.

Do:

- preserve evidence,
- preserve confidence,
- preserve source labels,
- version detector logic,
- version taxonomy,
- version benchmark data,
- keep evaluation reproducible.

---

## 24. Immediate Milestone

The next concrete milestone is:

> Run CoachMe boxing pose sequences through the current detector and produce a benchmark report comparing detected issues with mapped coach-labelled ground truth.

Target report:

```text
Overall Precision: ...
Overall Recall: ...
Overall F1: ...

Guard F1: ...
Rotation F1: ...
Body Position F1: ...
Stance F1: ...
Punch Mechanics F1: ...

Top false positives:
...

Top false negatives:
...
```

Once this exists, every future change can be objectively evaluated.

---

## 25. Long-Term Improvement Loop

```text
Current Production Detector
↓
Benchmark
↓
Weakest Category
↓
AI / Developer Proposes ONE Change
↓
Candidate Detector
↓
Full Benchmark
↓
Better + No Major Regression?
├─ NO → Reject
└─ YES → Human Review
            ↓
          Promote
```

---

## 26. Core Principle

> **Use CoachMe as independent boxing ground truth, not merely as training data.**

The most valuable initial use is:

```text
coach-labelled pose sequence
vs
our detector output
```

That gives the project a repeatable way to answer the question:

> **Did the boxing analysis actually get better?**
