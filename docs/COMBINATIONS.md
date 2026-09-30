# Combinations

Detecting, scoring and drilling punch combinations — the V2 feature that turns a
stream of individual punches into boxing the app understands. Built on the
existing pose + punch pipeline ([`POSE_ANALYSIS.md`](POSE_ANALYSIS.md)); nothing
here re-does pose maths.

Code: `app/lib/analysis/combination.dart`,
`combination_analysis.dart`, `drill_matching.dart`,
`app/lib/data/combination_library.dart`,
`app/lib/ui/screens/combination_*_screen.dart`.

## Pipeline

```
PoseSequence
   │  PunchDetector + classifyPunch            (existing)
   ▼
List<PunchEvent>  (side + motion class + timing)
   │  detectCombinations(sequence, punches, stance, {maxGapMs = 1200})
   ▼
List<Combination>  (numbered sequences, e.g. 1-2-3)
   │  analyzeCombination(...)   per combo
   ▼
List<CombinationAnalysis>  (0–100 score + coded issues)
   │  evaluateDrill(targetNumbers, analyses)   when drilling a target
   ▼
DrillResult  (per-attempt match + aggregate)
```

## Detection (§9)

`detectCombinations` is a pure function over the `PunchEvent` list the detector
already produces. Punches thrown within `maxGapMs` (end-to-start) are one
combination; runs shorter than two punches are single punches, not combinations.
Classified motion + hand becomes a conventional number via `PunchNumbering`
(§7, configurable, southpaw-aware): 1 jab, 2 cross, 3 lead hook, 4 rear hook,
5 lead uppercut, 6 rear uppercut. An unclassifiable punch becomes `0` and lowers
the combination's confidence. `AnalysisContext.combinations` caches the result
like `punches`.

## Execution scoring (§10)

`analyzeCombination` scores one combination's *execution*, not just whether it
matched, reusing the frontal-honest signals scoped to the combo window:

- **recovery between punches** — the earlier hand back near guard before the next;
- **guard during each punch** — the non-punching hand stays up;
- **end balance** — hips back over the base after the last punch;
- **rhythm** — captured as a descriptive `rhythm_cv` metric, not a fault.

Each issue carries a taxonomy `code`, `severity` and `confidence`. The score
starts at 100 and loses points per issue by severity; the round's mean is the
`combination_execution_score` component metric (§27). Depth-dependent judgements
(weight transfer, forward lean) are deliberately left out — the same reliability
rule as the Phase 2 rules.

## Drills (§14, §15)

`CombinationLibrary` is the punches-only starter set of target combinations
(id, name, numbers, difficulty, description, coaching points; `videoAsset` is
null until footage exists). `evaluateDrill(target, analyses)` compares each
detected combination against the target, producing a `DrillResult`: per-attempt
`sequenceMatch` + execution score, and an aggregate (match rate, average score
over matched attempts only — a mis-thrown combination doesn't move the technique
score).

The **live loop**: the detail screen's "Start drill" opens the shared
`RoundCaptureScreen`, which runs the same pre-flight as a routine — the
`CameraCheckScreen` framing check + "I'm in frame" + 5-second count-in — then
records the round, runs pose → rules → combination detection + scoring under
`SessionType.combinationDrill`, and returns the analysis. The detail screen then
`evaluateDrill`s it against the target and renders the `DrillResult` — attempts,
execution scores and the checkpoint pass rates — straight away. Recorder,
estimator and the analysis step are injectable, so the whole loop is testable
without a camera or MediaPipe.

**AI review of a drill.** In an AI analysis mode, once the on-device result is
on screen the drill's AI review runs in the background
(`BackgroundAnalysis.reviewWithAi`): it reuses the pose and analysis the drill
just saved — no second tracking pass — runs the profile's AI mode through
`RoundCoach` with the drill target, and saves the enriched analysis back (so
"Watch round" shows it too). It holds the screen awake, publishes progress
(uploading → reviewing → saving) and toasts when done. The drill result shows
an "AI coach" badge while it runs, then the coach's read and, with Full AI
review, the AI's verdict per checkpoint: video-only checkpoints become "AI:
OK" / "AI: missed", and measured ones the AI failed get "· AI flagged". One
weekly AI analysis per drill, refunded if the call fails; offline mode skips
it.

Both the drill and the standalone **shadow-boxing** round (home → Shadow boxing)
run through `RoundCaptureScreen` with a chosen **length** (1–3 min via
`DurationSelector`): `maxDuration` drives a live countdown and auto-stops the
round (you can still stop early). The shadow round captures under
`SessionType.shadowBoxing`, shows the feedback, and saves a one-round
`SessionRecord` (`domain/shadow_round.dart`) to History + the weekly balance.
The home page lists both modes as accordions.

## Technique checkpoints (drill standards)

A combination or technical drill isn't judged like free shadow boxing: each
punch has specific things the drill is looking for, and those outweigh general
faults everywhere the round is analysed.

**Catalogue** — `analysis/checkpoints.dart`, per punch number, so any
combination is its punches' checkpoints in order (`Checkpoints.forSequence`;
a repeated punch is graded once):

| Punch | Checkpoints |
| --- | --- |
| 1 Jab | snaps back after extension |
| 2 Cross | full rotation · at shoulder height or higher (rear shoulder covers the chin) · lead hand back protecting the face · elbows in |
| 3 Lead hook | level at shoulder height, not downward · arm at ~90° · full hip rotation · rear hand back defending the face |
| 4 Rear hook | mirror of the lead hook |
| 5 / 6 Uppercuts | driven from the legs, no wind-up · other hand defending the face |

Each checkpoint has a stable `id`, the full standard (`detail`), a taxonomy
`faultCode`, the coach's `failCue`, and how the pose engine checks it
(`CheckpointCheck`). Codes added for them: `GUARD_008` elbows out,
`PUNCH_001` punch below shoulder height, `PUNCH_002` hook arm angle,
`PUNCH_003` hook not level (taxonomy v3).

**Where the target comes from** — `DrillContext.targetSequence`: the
combination drill passes `combo.numbers`; technical exercises declare
`Exercise.targetSequence` (jab mechanics `[1]`, one-two `[1, 2]`, hook
mechanics `[3]`, uppercut mechanics `[5, 6]`, stepping/double jab, check
hook). It's persisted on `RoundClip.targetSequence` so a re-analysis grades
the same checkpoints. Free work (shadow boxing, non-punch exercises) has none.

**On-device grading** — `analysis/checkpoint_evaluation.dart` grades each
checkpoint on every punch it covers (torso-length thresholds in
`CheckpointConfig`; each with its own confidence, all 2D/single-camera):

| Check | Passes when |
| --- | --- |
| snap-back | retraction ≤ 1.5× the extension time (+80 ms grace) |
| rotation | shoulder travel vs hips ≥ 0.12 (same measure as `hip_rotation`) |
| shoulder height | fist ≤ 0.2 below the shoulder at the peak |
| guard hand at face | other fist ≤ 0.55 from the nose (fallback: ≤ 0.35 below its shoulder) |
| hook level | fist ≤ 0.25 below the shoulder and elbow not > 0.3 above the fist |
| hook arm angle | elbow 65–125° at the peak |
| video only | never graded on-device (elbows in, uppercut leg drive) — the AI grades it |

**Weight** — a failed checkpoint:
- costs 1.5× in the combination execution score (`kCheckpointPenaltyWeight`)
  and replaces the general issue of the same fault at the same instant;
- becomes its own observation (`ruleId: checkpoint`), severity by fail rate
  (≥ 50% of reps major, ≥ 25% moderate), ranked ahead of all general faults —
  so it leads the corrections, the summary and the moments — and supersedes
  the general rule's report of the same code;
- a checkpoint held on ≥ 80% of at least 3 reps becomes a positive note.
Tallies per checkpoint are on `RoundAnalysis.checkpointTallies` and shown in
the drill result (passed/graded; for video-only checkpoints the AI's verdict
once the drill's AI review lands, "AI review" until then).

**AI** — the structured input carries `drill_target` (sequence, checkpoints,
on-device results) and both prompts lead with a punch-by-punch brief. Full AI
review must grade every checkpoint, tag failures with `"checkpoint": <id>`,
and rank them first; `AiReview` ranks a checkpoint finding one severity level
higher. This applies wherever the AI runs on a drill: the combination drill's
background review, session rounds of technical exercises, and re-analysis from
the review screen.

## Feature flags

`FeatureFlags.combinationDetection` and `combinationDrills` gate the analysis and
the UI. Both are on.

## Not yet

- **Instructional videos** — not sourced; the UI degrades to the written sequence
  + coaching points.
- **Defensive actions** (slips, rolls) are excluded from the library and the
  numbering — they need their own event model (§20), reserved not built.
