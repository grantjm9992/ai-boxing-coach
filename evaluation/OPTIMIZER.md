# CoachMe detector optimiser

Self-iterating tuner for the on-phone analysis engine's detector thresholds,
scored against the CoachMe boxing pose benchmark (coach-labelled ground truth,
independent of our own model). Implements the plan's §16/§17/§22-Phase7/§25 loop.

## What it does

Runs the analysis engine **in-process** over every CoachMe clip's `pose.json`,
compares the detected faults against the coach-labelled `ground_truth.json`, and
hill-climbs the detector thresholds (one knob at a time) to maximise a benchmark
objective — keeping a change only if it passes the promotion gate (no category
regression, no hallucination rise, no major-recall drop). It sweeps until a full
pass accepts nothing (a local optimum = the "optimal solution" it converges to),
with optional random restarts to escape local optima.

The winner is written as a **`TunedProfile` JSON** — a small, reviewable set of
threshold overrides. That artifact is the portable thing that improves the
on-phone analysis; see `PORTING.md` for moving it into the Dart engine.

## Requires the engine interpreter

The harness imports the engine (numpy), so use the pyenv engine python, not the
bare sandbox one:

```bash
PY=~/.pyenv/versions/3.10.0/bin/python3
```

## Run it

```bash
# Converge on train, report the winner on the held-out test split (overfit check)
$PY optimize.py ../datasets/coachme/train --validate ../datasets/coachme/test

# Objective + gate knobs
$PY optimize.py ../datasets/coachme/train \
    --objective weighted_f1 \        # or overall_f1 / overall_recall
    --category-tol 0.05 \            # max per-category F1 drop the gate allows
    --restarts 8 --seed 1 \          # random restarts to escape local optima
    --out tuned/my-run.json

# Resume/continue from a previous winner (loop-friendly)
$PY optimize.py ../datasets/coachme/train --resume tuned/coachme-detectors-v1.json
```

Leave it looping: it keeps running restarts until none beats the best, then
stops. To keep it on a wall-clock cadence, drive it with the harness `/loop`
(`--resume` the previous winner so each pass continues rather than restarts).

## Result (this branch)

Tuned on `train`, reported on **held-out** `test` — the gain generalises:

| Split          | Baseline F1 | Tuned F1 | rotation | body_position | guard |
|----------------|-------------|----------|----------|---------------|-------|
| train          | 0.112       | 0.260    | 0→0.562  | 0.225→0.345   | 0.279→0.300 |
| test (held-out)| 0.163       | 0.313    | 0.240→0.649 | 0.364→0.500 | 0.188→0.207 |

No hallucination rise, no category regression. Winner: `tuned/coachme-detectors-v1.json`.

Categories with no detector yet (balance/footwork/lean/tension) stay at 0 — those
are *missing rules*, not mis-tuned ones, so they're correctly outside the search
space (`mappings/param_space.py`). They are the next detectors to build, not
thresholds to move.

## How the pieces fit

```
pose.json ─┐
           ├─ Harness (in-process engine, TunedProfile injected) ─┐
gt.json  ──┘                                                      ├─ scorer ─ runner.aggregate ─ metrics
                                                                  │
mappings/param_space.py ── optimize.py hill-climb ── promotion gate (runner.compare) ── TunedProfile JSON
```

- `mappings/` — versioned, isolated mapping registries (joints, phrase map,
  param space, tuned profile). A new version never disturbs a frozen one.
- `harness.py` — loads a split once, scores any `TunedProfile` in-process; its
  numbers are identical to the disk `runner.py run`, just ~1000x faster.
- `optimize.py` — the self-iterating loop.
