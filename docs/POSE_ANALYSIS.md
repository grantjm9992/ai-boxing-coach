# Pose analysis

The on-device pipeline that turns a recorded round into structured feedback,
with no network and no AI. This is the whole of the offline analysis mode and
the base every other mode builds on.

Code: `app/packages/pose_landmarker/` (native plugin),
`app/lib/analysis/` (pure engine), `app/lib/services/pose_estimator.dart`,
`app/lib/services/round_analyzer.dart`.

## Pipeline

```
RoundClip (mp4)
   │  MediaPipePoseEstimator  ── native pose_landmarker plugin
   ▼
List<RawPoseFrame>  ── rawFramesToSequence() ──►  PoseSequence
   │  PoseOnlyAdapter
   ▼
RuleEngine over the sequence  ──►  Observations
   │  synthesis (deterministic, template-based)
   ▼
RoundAnalysis  (summary, prioritised corrections, positive notes, metrics, flagged moments)
```

`RoundAnalyzer.analyze()` orchestrates it and persists the result via
`AnalysisStore` (see [`RECORDING_STORAGE.md`](RECORDING_STORAGE.md)). In the AI
modes it then layers a vision model on top — see
[`AI_INTEGRATION.md`](AI_INTEGRATION.md).

## Native pose estimation

`app/packages/pose_landmarker/` is a Flutter plugin wrapping MediaPipe's Pose
Landmarker (33 landmarks). `PoseLandmarkerPlugin.kt` decodes the clip frame by
frame and runs detection.

- **Frame decode.** The clip is stream-decoded via `MediaCodec` rather than
  re-seeking per frame — a large win over seeking.
- **YUV → Bitmap.** Each decoded `YUV_420_888` frame is converted to
  `ARGB_8888` in a single integer BT.601 (full-range) pass, stride-aware for
  planar and semi-planar layouts. (This replaced an earlier
  `YUV → NV21 → JPEG-encode → JPEG-decode → Bitmap` round trip — the dominant
  per-round cost. Resolution and frame rate are unchanged; the pixels handed to
  MediaPipe are the same, minus the old lossy JPEG step.)
- **Serialised runs.** Native pose runs are serialised with a labelled stall
  guard, and the Dart side times the run out, so a wedged decode surfaces
  instead of hanging a release build.

`MediaPipePoseEstimator` (`services/pose_estimator.dart`) exposes progress and,
when done, a `PoseAnalysisResult`: the `PoseSequence` the rules consume plus
mechanical facts — frames analysed, the fraction of frames with the full body in
view (shoulders, hips, ankles), and elapsed time. That visibility fraction
drives the honest "we can see you" indicator.

### Sampling rate

Frame rate is kept deliberately modest (~16fps) and is **not** reduced for
speed: the rules derive punch velocity from frame timestamps, and dropping
frames would cost detection quality.

## The pure glue

`analysis/pose_estimation.dart` converts the plugin's raw 33-landmark frames
into a `PoseSequence`, keeping only the landmarks the engine models (by
MediaPipe index). Frames with no detection become empty frames — their
timestamps still matter and the rules already treat missing landmarks as NaN.
This file has no plugin or platform-channel dependency, so it's unit-tested
without a device.

## The rule engine

A Dart mirror of the Python reference under `src/boxing_coach/analysis/`.

- **`Rule`** (`analysis/rule.dart`) — one technique check over a round. Adding a
  rule is one subclass; nothing is discovered implicitly. Each rule declares the
  drill focus tags it's relevant to, so the engine skips irrelevant rules.
- **`RuleEngine`** (`analysis/engine.dart`) — decides which rules apply (by
  style/school profile and drill focus), runs each, gathers observations, and
  isolates a single failing rule so one bad rule can't sink the analysis.
- **Shipped rules** (`analysis/rules/`): the v0.5 set — `guard_return`,
  `hands_up`, `head_movement`, `hip_rotation`, `footwork`, `school_adherence` —
  plus the V2 additions `body_lean` and `balance`. `engine.dart` splits these
  into `v05Rules()` (the frozen Dart↔Python golden-parity contract) and
  `v2Rules()`; `defaultRules()` is both.

Rules emit `Observation`s carrying a `Severity`
(`positive`/`minor`/`moderate`/`major`), a `SkillCategory`, a stable fault
`code` (taxonomy in `analysis/error_codes.dart`) and a `confidence` (0..1).
The V2 analyzers are scoped to what a single **frontal** view reads honestly
(lateral torso lean, hips over the base of support) and set a sub-1.0
confidence; depth-dependent faults are held back rather than inferred
unreliably. The adapter drops sub-threshold observations from the user report
but keeps them on `RoundAnalysis.lowConfidenceObservations` for the AI layer
(§12). Every round also carries its `SessionType` and `analysisVersion`.

Combination detection and execution scoring build on the punch stream — see
[`COMBINATIONS.md`](COMBINATIONS.md).

## Punch detection & classification

`analysis/punch_classifier.dart` (mirror of the Python classifier) classifies a
detected punch from the wrist's start→peak path plus the elbow angle at the
peak (a reach-based fallback when the elbow isn't visible). Lengths are in
torso-lengths. Single-view 2D separates punch types unevenly, so the type is a
useful signal, not ground truth.

## Synthesis into RoundAnalysis

`PoseOnlyAdapter` (`analysis/pose_only_adapter.dart`) runs the engine, then
synthesises the observations into the `RoundAnalysis` the coach speaks: a
summary, prioritised corrections, positive notes, metrics, and flagged moments.
Synthesis is deterministic and template-based on purpose — v0.5 ships with no
model in this path. The style/school profile is resolved from the drill, and
`metrics.values` carries the round-profile features that feed national-school
classification, at full parity with the Python reference.

`RoundAnalysis` (`analysis/round_analysis.dart`) is the structured shape the
coach, the review screen, the history rollup and the Supabase schema all speak.

## Calibration against Python

The Dart engine is a port; `src/` is the reference. A round's pose data can be
exported and run through the Python engine to check parity (the calibration
loop). Golden tests in `app/test/golden_*` pin observations, punches, body
scale and profiles against reference fixtures.
