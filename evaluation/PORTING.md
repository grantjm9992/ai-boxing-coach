# Porting a TunedProfile into the on-phone (Dart) engine

The optimiser tunes the **Python reference engine** against CoachMe and writes a
`TunedProfile` JSON (e.g. `tuned/coachme-detectors-v1.json`). The shipping
on-phone engine is the **Dart parity port** in `app/lib/analysis/rules/`, whose
config fields mirror the Python ones 1:1 (snake_case → camelCase):

| TunedProfile key                     | Dart field (`app/lib/analysis/rules/…`)          |
|--------------------------------------|--------------------------------------------------|
| `hands_up.drop_margin`               | `hands_up.dart` `dropMargin`                     |
| `hands_up.max_down_fraction`         | `hands_up.dart` `maxDownFraction`                |
| `guard_return.return_radius`         | `guard_return.dart` `returnRadius`               |
| `guard_return.drop_margin`           | `guard_return.dart` `dropMargin`                 |
| `guard_return.healthy_return_rate`   | `guard_return.dart` `healthyReturnRate`          |
| `hip_rotation.min_shoulder_drive`    | `hip_rotation.dart` `minShoulderDrive`           |
| `hip_rotation.min_peak_reach`        | `hip_rotation.dart` `minPeakReach`               |
| `knee_bend.straight_deg`             | (Dart has no knee_bend rule — 3D only, see below)|

Porting = updating those Dart config defaults with the tuned values, then
re-running the Dart golden tests.

## IMPORTANT: which thresholds actually transfer to the 2D phone view

CoachMe pose is **trustworthy 3D SMPL**; the phone runs a **frontal 2D**
estimate. A threshold only transfers cleanly when its feature means the same
thing in both. Per the plan's two-benchmark principle (§19), the CoachMe pose
benchmark validates the *detection logic*; the *2D pipeline* still needs the
own-video benchmark before a 3D-tuned number ships to the phone.

- **Transfers cleanly — guard (`hands_up`, `guard_return`).** These are
  torso-relative wrist-vs-shoulder/launch heights, the same geometry frontally
  and in 3D. Safe to port and expect a similar effect. **Recommended now.**

- **Do NOT port blindly — `hip_rotation.min_shoulder_drive`.** The optimiser
  found 0.28 (up from 0.12) a big win on CoachMe, but it drove that gain off the
  **z-axis** shoulder travel that only trustworthy 3D has. On the phone's 2D
  view rotation lives in the image plane and reads differently (the standing
  rotation caveat in the rule's own docstring). Re-tune this one against the
  own-video 2D benchmark before shipping it to the app.

- **3D-only — `knee_bend.straight_deg`.** `knee_bend` self-gates on
  `depth == metric_3d`, so it is silent on the 2D phone engine and there is no
  Dart rule to port to. It matters for the future multi-camera 3D rig, not the
  current phone. Keep it in the profile; it simply no-ops on 2D.

## Suggested split

Port the **guard** overrides to Dart now (they transfer and lift guard F1). Hold
the **rotation/knee** overrides against the 3D path (CoachMe today; the camera
rig later), and re-derive their 2D equivalents with a `optimize.py` run over the
own-video benchmark once that has coach-reviewed labels (plan §19-B).

## Why keep the artifact rather than bake numbers into code

A `TunedProfile` is versioned data: it records *what changed and to what*, is
diffable, and both engines can load it. Baking the numbers into engine source
loses that provenance and couples the two engines' release cycles. The Python
side already loads it via `TunedProfile.to_style_profile()`; a matching Dart
loader (read the same JSON into the rule configs) is the clean long-term bridge.
