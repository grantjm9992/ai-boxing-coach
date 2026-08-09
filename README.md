# boxing-coach (vision-analysis skeleton)

The part of the AI boxing coach that decides whether the product can exist:
**offline video → pose estimation → coach rules → structured, coach-voiced
observations.** No app, no timer, no sessions. If this produces observations a
real boxer agrees with, everything else is engineering. If it can't, the
product needs rethinking — better to find that out here.

```
video ──▶ PoseEstimator ──▶ PoseSequence ──▶ VisionAnalysisAdapter ──▶ RoundAnalysis
          (MediaPipe)          (keypoints/frame)   (PoseOnly: rules)      (summary, corrections,
                                                                          metrics, flagged moments)
```

## Quick start

See the output right now, with no video and no MediaPipe:

```bash
python examples/demo.py
```

That runs a synthetic round (two clean jabs, then one where the hand drops,
feet planted) through the real analysis path and prints the coach report.

To analyse a real clip:

```bash
pip install -e ".[vision,dev]"          # pulls in mediapipe + opencv
python -m boxing_coach.cli myround.mp4 --stance orthodox
python -m boxing_coach.cli myround.mp4 --focus jab defence --json > out.json
```

### Annotated stills

Add `--stills DIR` to save one annotated frame per correction — the video frame
at that moment with the pose skeleton drawn and the at-fault body part circled
in red, captioned with the coaching cue. Each correction's `still_path` points
at its PNG (in the report and in `--json`).

```bash
python -m boxing_coach.cli myround.mp4 --stance orthodox --stills ./stills
```

Only corrections tied to a moment get a still; round-level ones (e.g. flat
footwork) have no single frame to show. Rendering lives behind a lazy `cv2`
import in `rendering/`, so it never touches the engine or its tests.

Run the tests (engine only — no MediaPipe needed):

```bash
pytest
```

## Design

Two seams, because the spec named two axes of change:

- **`PoseEstimator`** (`pose_estimation/`) — swap MediaPipe for MMPose without
  touching a single rule. MediaPipe/opencv are imported lazily, so the engine
  and tests never require the CV stack.
- **`Rule`** (`analysis/rules/`) — the coach's knowledge. Adding a technique
  check is one subclass added to `default_rules()`; nothing else changes.

Everything in between is estimator-agnostic:

- `domain/` — plain data types (`PoseSequence`, `Observation`, `Correction`,
  `RoundAnalysis`), matching the spec's vocabulary and DB schema.
- `analysis/features.py` — shared derived features computed **once** per round:
  a person-and-camera-invariant `body_scale` (median torso length) and
  `PunchDetector` (adaptive, relative to the boxer's own retracted baseline —
  no magic pixel thresholds).
- `analysis/context.py` — `AnalysisContext` bundles the sequence + drill +
  features; every rule reads what it needs from it.
- `adapters/pose_only.py` — the MVP adapter. Runs the rules and synthesises the
  `RoundAnalysis` deterministically. A VLM adapter would subclass
  `VisionAnalysisAdapter` and enrich this step.

All distances are expressed in **torso-lengths**, so thresholds hold across
different people and camera distances instead of being tied to pixels.

## The starter rules

Five rules, mapping onto the spec's "detectable in v1" list. Each has its own
tunable config dataclass so you can calibrate against your own footage.

| Rule | Detects | Category |
|---|---|---|
| `guard_return` | hand not returning to guard after a punch (drops / left extended / slow) | defence |
| `hands_up` | hands drifting down *between* punches | defence |
| `footwork` | rooted / flat-footed for a whole round | footwork |
| `head_movement` | head never leaving the centre line | head movement |
| `hip_rotation` | rear straight thrown arm-only, no rotation | offence–straight |

## Punch types

The detector labels each punch with a **motion class** — `STRAIGHT`, `HOOK`,
`UPPERCUT` (or `UNKNOWN`) — from the wrist's start→peak path and the elbow angle
at the peak (a bent elbow separates a hook/uppercut from an extended straight;
vertical rise separates the uppercut). Side + stance then name it: a lead
straight is a *jab*, a rear straight a *cross*, and so on (`punch_name`). The
round's `punch_mix` (e.g. `{"jab": 3, "cross": 1}`) rides on the metrics.

This is what lets rules target the right punch: `hip_rotation` now judges only
the rear **straight**, since a hook or uppercut turns over differently and
shouldn't be measured against a cross's shoulder-drive. Classification is a
swappable step (`analysis/punch_classifier.py`) — single-view 2D reads the
uppercut and straight clearly but the hook least well, so treat the type as a
strong signal, not ground truth.

## Fighting styles

"Correct" is style-dependent — judging every fighter against a textbook high
guard gives a shell fighter the wrong advice. A **`StyleProfile`** tunes and
gates the rules per style: it switches off rules that don't apply and overrides
the thresholds that legitimately differ.

```bash
python -m boxing_coach.cli myround.mp4 --style philly_shell
```

| Style | What it changes |
|---|---|
| `high_guard` | the neutral default — every rule on, default thresholds |
| `philly_shell` | lead hand rides low on purpose → `hands_up`/`guard_return` judge the **rear hand only** |
| `peek_a_boo` | hands high, constant head movement → held to a **higher `head_movement` bar** |
| `out_boxer` | defends with range → `head_movement` **off**, `footwork` held to a higher bar |

Style is per round (it lives on `DrillContext`), so it varies without rebuilding
the rule set — the resolved profile rides on the `AnalysisContext` and each rule
reads its config from it. Adding a style is a `Style` enum member plus one entry
in `analysis/style_profiles.py`. Like the thresholds, the profiles are starting
points to calibrate, not gospel.

## Adding a rule

```python
from boxing_coach.analysis.rule import Rule
from boxing_coach.domain.analysis import Observation, Severity, SkillCategory

class ChinTuckRule(Rule):
    id = "chin_tuck"
    focus_tags = frozenset({"defence"})   # empty = always runs

    def evaluate(self, context):
        # read context.sequence / context.punches / context.body_scale
        return [Observation(rule_id=self.id, category=SkillCategory.DEFENCE,
                            severity=Severity.MINOR, coaching_text="...")]
```

Add it to `default_rules()` and it's live. Write a fixture in `tests/fixtures.py`
that exhibits the fault and a test that asserts it fires (and stays quiet on a
clean fixture) — that's the validation loop the whole skeleton exists to serve.

## Honest limitations (read before trusting output)

- **Front-view 2D is weak on depth.** A straight punch thrown at the camera
  foreshortens, and rotation lives mostly in depth. `hip_rotation` leans on
  MediaPipe's estimated `z` and is the **least reliable** rule from a single
  front camera — the first candidate for a second angle or the VLM layer. The
  synthetic fixtures assume an angled/side camera where punches extend in-plane.
- **Thresholds are guesses until calibrated.** The defaults are reasonable
  starting points, not tuned values. The real work is recording yourself doing
  things right and wrong, and adjusting each rule's config until observations
  match reality. That's `--json` output plus your own eyes.
- **Punch typing is uneven from one camera.** The classifier separates the
  uppercut (vertical) and straight (extension) well, but the hook — a horizontal
  arc with a bent elbow — foreshortens on a head-on view, and the detector only
  sees punches that push the wrist away from the shoulder. It's a strong signal,
  not ground truth, and the first place a second angle or the VLM layer helps.
- **Style profiles are coarse.** Four styles exist (`StyleProfile`), enough to
  stop the worst misfires — a Philly shell's low lead hand is no longer flagged,
  an out-boxer isn't nagged about head movement. But each profile is a handful
  of threshold tweaks and rule on/offs, not a real model of the style. A shell's
  lead hand still isn't checked for returning to *its* guard (across the body),
  only exempted; that finer per-style technique modelling is future work.
- **This is 5 rules, not 30.** The spec's domain value is in the rule library.
  The skeleton proves the pattern; the boxing expertise is what fills it out.

## Next validation step

Record 3–5 short shadow clips where you *deliberately* do specific things wrong,
run them through the CLI, and check whether each observation matches what you
actually did. If yes, the product can exist — expand the rules. If the pose data
isn't clean enough, that's the thing to solve before writing more rules.
