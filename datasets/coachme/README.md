# CoachMe BX — 3D reference dataset (NOT for app calibration)

Source: [CoachMe](https://github.com/MotionXperts/MotionExpert) (ACL 2025, Apache-2.0).
204 beginner jab/cross clips, each with 3 independent boxing-coach instructions
and a 22-joint **SMPL 3D** pose sequence. The raw videos are withheld by the
authors for athlete privacy.

## What this is good for
- **Taxonomy / prioritisation** — real coach language about beginner faults.
  It already drove three taxonomy additions (chin, knee-bend, tension) and tells
  us which faults coaches care about most (rotation dominates).
- **Developing 3D-gated rules** — e.g. `knee_bend` (POS_006), which runs only on
  trustworthy 3D (`pose.json` meta `depth: metric_3d`). This is the template for
  the eventual multi-camera ring rig.

## What this is NOT good for — do not do these
- **Calibrating the in-app pose analysis.** The app runs on **2D monocular
  mediapipe**; this is **3D SMPL** in a different coordinate space. A threshold
  tuned to these coordinates will not transfer to the app's — you'd be
  calibrating for the wrong domain. Bridging would require the videos (run
  through *our* mediapipe), which are withheld.
- **Exercising round-level rules.** Clips are ~1 s single reps; rules that need a
  round (balance, body-lean, footwork mobility, combinations, guard recovery)
  can't activate, so scores here understate them.

## Provenance / caveats
- Labels are **trusted in good faith** (`status: reviewed`) — the coach *text* is
  genuine, but `observations` are a machine phrase-map of that text and may be
  **incomplete** (`unmapped_sentences` holds un-encoded faults). Absence of a
  code is **not** a coach "all-clear". Clips where nothing mapped stay `draft`.
- Pose is `pose.json` (our wire format, converted from the SMPL `.pkl` by
  `evaluation/smpl_to_pose.py`).

**Bottom line:** treat CoachMe as a *what-to-build* and *3D-rule development*
reference. To actually iterate the app's accuracy you need clips where we hold
the video (app-domain 2D pose) + coach labels — which this dataset cannot
provide.
