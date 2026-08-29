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
`evaluateDrill`s it against the target and renders the `DrillResult`. Recorder,
estimator and the analysis step are injectable, so the whole loop is testable
without a camera or MediaPipe.

`RoundCaptureScreen` is shared with the standalone **shadow-boxing** round (home
menu → Shadow boxing), which captures the same way under
`SessionType.shadowBoxing`, shows the round feedback, and saves a one-round
`SessionRecord` (`domain/shadow_round.dart`) to History + the weekly balance.

## Feature flags

`FeatureFlags.combinationDetection` and `combinationDrills` gate the analysis and
the UI. Both are on.

## Not yet

- **Instructional videos** — not sourced; the UI degrades to the written sequence
  + coaching points.
- **Defensive actions** (slips, rolls) are excluded from the library and the
  numbering — they need their own event model (§20), reserved not built.
