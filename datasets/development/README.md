# Own-video 2D benchmark (plan §19-B)

The second benchmark axis, complementing the CoachMe **3D** pose benchmark: real
footage through the phone's actual **monocular 2D** pipeline
(video → mediapipe → the same engine). Its job is to validate detectors *as they
behave on the phone* — where monocular z is unreliable, so depth-gated rules
(knee bend) stay silent and rotation is judged in the image plane. This is where
rotation must be re-tuned before any CoachMe-3D rotation number ships (the 3D
`min_shoulder_drive` win does **not** transfer — see `evaluation/PORTING.md`).

## Layout

```
datasets/development/<clip>/
    ground_truth.json     # coach/manual labels (independent truth — see below)
    pose.json             # 2D mediapipe pose, written by video_to_pose.py
    predictions/…         # optional, written by predict.py
```
The source videos live at the repo root and are named by `source_file` in each
`ground_truth.json`.

## Workflow

```bash
cd evaluation
# 1. ingest raw video -> 2D pose.json (needs mediapipe + the pose model)
python3 video_to_pose.py ../datasets/development

# 2. run / iterate the optimiser on the 2D set (engine interpreter)
~/.pyenv/versions/3.10.0/bin/python3 optimize.py ../datasets/development \
    --allow-draft --objective overall_f1 \
    --resume tuned/coachme-detectors-v1.json   # start from the applied profile
```

The loop is iterative by construction: it hill-climbs, keeps only gate-passing
changes, and converges. Add clips and re-run; `--restarts N` escapes plateaus
(useful on small sets, but see the overfitting warning below).

## The hard rule: labels are INDEPENDENT truth, never the engine's own output

Ground truth must come from a human (you recording deliberate faults, or a coach
review). Do **not** label a clip by running the engine and trusting its output —
that is circular self-grading (plan §15/§26) and makes the benchmark meaningless.
The engine may *seed a draft* for a human to correct (`status: draft`), but a
label is only trustworthy once a person has reviewed it (`status: reviewed`).

## What this set can measure TODAY vs what it needs

The three seed clips are elite/instructional footage, not the target user:

| clip          | rotation label        | use                                   |
|---------------|-----------------------|---------------------------------------|
| clip          | (none — guard fault)  | guard signal                          |
| clip_bivol    | `ROT_001 present:false` | rotation **false-positive control**   |
| clip_bivol_2  | (none)                | guard signal                          |

So today it measures rotation **precision** (don't flag a good rotator — and the
engine currently *does* over-fire: 3 rotation FPs at the default threshold,
which lowering `min_shoulder_drive` reduces). It **cannot** measure rotation
**recall**: there is not a single clip labelled with a *real* rotation fault
(`ROT_001 present:true`). Tuning on three clips also overfits — a restart run
happily wrecked the validated guard thresholds to squeeze this set, and the gate
rejected it. **Three clips is a plumbing demo, not a trustworthy re-tune.**

## To actually re-tune rotation for the phone — record these

Front-view (and ideally a 45°/side repeat), one fault per clip, ~1–2 rounds
each, labelled by a human. From the plan's §19-B list, the rotation-critical set:

- **cross with poor rotation** (squared up, arm-only)  → `ROT_001 present:true`
- **cross with good rotation** (full hip/shoulder turn) → `ROT_001 present:false`
- 1-2 with poor rotation on the cross
- a few of each across different fighters/body types (avoid overfitting one body)

Ten or so labelled clips (a real present:true/false split) is enough to make the
rotation recall/precision trade-off measurable, at which point
`optimize.py … --objective weighted_f1` re-tunes `hip_rotation` honestly for 2D,
and the winner ports to `app/lib/analysis/rules/hip_rotation.dart`.
