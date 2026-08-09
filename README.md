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
- **No punch *type* classification yet.** The detector finds punches and which
  hand; it doesn't distinguish jab vs hook vs uppercut. Several richer rules
  need that — it's the natural next feature.
- **This is 5 rules, not 30.** The spec's domain value is in the rule library.
  The skeleton proves the pattern; the boxing expertise is what fills it out.

## Next validation step

Record 3–5 short shadow clips where you *deliberately* do specific things wrong,
run them through the CLI, and check whether each observation matches what you
actually did. If yes, the product can exist — expand the rules. If the pose data
isn't clean enough, that's the thing to solve before writing more rules.
