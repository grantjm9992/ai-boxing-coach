# V2 implementation plan

The execution plan for [`ai_boxing_coach_v2_implementation_brief.md`](../ai_boxing_coach_v2_implementation_brief.md).
The brief reads as a greenfield architecture spec; the app is not greenfield. This
document reconciles the two: it says what already satisfies the brief, what is
genuinely new, and the order to build it in so each phase stands on the last.

Read the brief for *what* and *why*. Read this for *where in the code* and *in what
order*.

## What already exists (do not rebuild)

| Brief asks for | Already in `app/lib` |
|---|---|
| §2 Hybrid CV + AI architecture | The whole pipeline: `PoseSequence → PunchDetector → AnalysisContext → Rule/RuleEngine → RoundAnalysis`, AI layered on flagged frames. |
| §3 Standard vs Advanced execution modes | `analysis/analysis_mode.dart`: `offline` / `keyframe` / `fullFrame`. |
| §8 Punch classification | `analysis/punch_classifier.dart` (`classifyPunch` → straight/hook/uppercut) + `punch.dart` (`punchName` resolves jab/cross/lead-hook by stance). |
| §11 Analyzer seam | `analysis/rule.dart` (`Rule`) + `engine.dart` (`RuleEngine`). Existing rules: guard_return, hands_up, footwork, head_movement, hip_rotation, school_adherence. |
| §19 Replaceable analyzer interfaces | The `Rule` abstraction is exactly this. Do **not** introduce parallel `GuardAnalyzer`/`RotationAnalyzer` classes — add `Rule` subclasses. |
| §17–18 Structured AI I/O | `services/ai/coaching_prompt.dart` + `coach_vision_model.dart`. Needs a stricter output schema, not a new subsystem. |
| §21 Persistence | SQLite + Supabase sync (`services/sync`, `services/supabase`). Needs `analysis_version` + richer event storage. |
| §30–31 AI provider abstraction / proxy | `services/ai/vision_model.dart`, `openai_compatible_vision_model.dart`, backend `analyze` edge function + quota. |
| §13 Camera quality gate | `ui/screens/camera_check_screen.dart` (partial). |

Net-new subsystems: **combination detection**, **combination drills**, four new
**analyzer rules** (lean / body-position / balance / recovery), **confidence on
observations**, and **`session_type`**.

## Architectural decision: `session_type` vs `SessionPhase`

The brief's `session_type` (§4) collides with the existing `SessionPhase`
(warmup → conditioning → shadow → technical → cooldown). They are different axes:

- **`SessionPhase`** = position within a *guided session arc*. Stays as-is.
- **`SessionType`** (new) = the *analysis intent* for one recorded round: what it
  is and therefore which thresholds and expectations apply.

**Resolution:** `SessionType` is a property of the analysis input, not the session
timeline. Add it as a field on `DrillContext` (`analysis/drill.dart`) — that class
already means "what this round was supposed to be." Persist it on the round record.

- Standalone recordings (Shadow Boxing / Technical Work chosen from the home
  screen) set `SessionType` directly.
- Guided-session rounds derive it from the phase: `shadow` → `shadowBoxing`,
  `technical` → `technicalWork`, `conditioning`/bag → `heavyBag`, else
  `freeTraining`.

Rules read `context.drill.sessionType` to pick thresholds. This reuses the existing
seam with zero new plumbing in the rule engine.

Enum: `SHADOW_BOXING, HEAVY_BAG, TECHNICAL_WORK, COMBINATION_DRILL, FREE_TRAINING`.

## Cross-cutting, land in Phase 1 and honour everywhere after

- **Confidence** — add `double confidence` (0..1, default 1.0) to `Observation`
  (`round_analysis.dart`). New analyzers set it below 1.0 for camera-angle-sensitive
  reads (rotation, lean). Low-confidence observations are dropped from the user
  report or escalated to the AI layer (§12).
- **Error taxonomy** — introduce stable codes (`GUARD_001`, `ROT_001`, …) as an
  enum/const map. Add `String code` to `Observation`. Display text stays separate
  from identity (§25). Existing rules get codes retrofitted.
- **`analysis_version`** — const `"2.0.0"`, written onto every persisted analysis
  so we can re-run/compare later (§21).
- **Feature flags** — `shadow_boxing_v2`, `footwork_analysis`, `rotation_analysis`,
  `combination_detection`, `combination_drills`, `advanced_ai_analysis` (§22).
- **Component scores, not one number** — Guard / Balance / Footwork / Punch
  Mechanics / Combination Execution (§27). Extend `RoundMetrics.values`.

## Phase sequencing (dependency-ordered)

Ordered so each phase is independently shippable and testable, and nothing depends
on a later phase.

### Phase 1 — `session_type` + data-model spine
Resolves the axis decision above and lands the cross-cutting fields, so no later
phase has to migrate the data model again.
- Add `SessionType` enum; field on `DrillContext`; derive-from-phase helper.
- Add `confidence` + `code` to `Observation`; `analysis_version` to persistence.
- Feature-flag scaffold.
- **Done when:** a recorded round carries a `SessionType`, persists it, and round-
  trips through SQLite + Supabase; existing golden tests still pass.

### Phase 2 — New analyzer rules (on the existing `Rule` seam) — DONE
Pure additive rules; immediately visible in reports; no UI change.
- **Shipped:** `rules/body_lean.dart` (§11.1, lateral torso tilt) and
  `rules/balance.dart` (§11.7, hips vs base of support) — the two faults a
  single **frontal** view reads honestly. Both emit a `code` + a sub-1.0
  `confidence`; registered via `engine.dart` `v2Rules()`.
- **§12 confidence gate:** `PoseOnlyAdapter` drops observations below
  `minReportedConfidence` (0.5) from the user report.
- **Golden contract:** the golden observation/style tests were pinned to the
  frozen `v05Rules()` so V2 rules don't perturb the Dart↔Python fixtures.
- **Deliberately deferred** (not fabricated from a frontal projection — brief
  §12/§35): forward/back lean and knee-bend/"too upright" body position (§11.3)
  are depth-dependent; extended rotation (§11.2) beyond the existing
  `hip_rotation` rule; recovery (§11.6) is already covered by `guard_return`.
  These wait on a camera-view signal or side-view support.
- **Done:** fixture tests (`test/v2_rules_test.dart`) cover lean + off-balance
  fire/silent cases; both appear in reports with stable codes. Session-type
  threshold tuning lands with the analyzers that need it in later phases.

### Phase 3 — Combination detection — DONE
A pure function over the `List<PunchEvent>` the `PunchDetector` already produces.
- `analysis/combination.dart`: `Combination` model + `PunchNumbering` (§7,
  configurable, southpaw-aware) + `detectCombinations(sequence, punches, stance,
  {maxGapMs = 1200})` grouping punches into numbered sequences; unknown punches
  become `0` and lower the combo confidence.
- Cached `AnalysisContext.combinations` getter (mirrors `punches`); surfaced on
  `RoundAnalysis.combinations` (persisted) + a `combinations_detected` metric,
  gated by `FeatureFlags.combinationDetection` (now on).
- **Done:** `test/combination_test.dart` distinguishes `1-2-3` from `1-3-4` from
  an unknown sequence, plus gap-splitting, southpaw, single-punch and JSON cases
  (acceptance criterion §34).

### Phase 4 — Combination-execution analysis
Turns "matched = true" into coached feedback (§10). Depends on Phase 2 rules +
Phase 3 combos.
- Per-combination checks (recovery between punches, guard between punches, weight
  transfer, final position) reusing Phase 2 analyzers scoped to a combo window.
- Component "Combination Execution" score.
- **Done when:** a detected `1-2-3` returns sequence match + per-issue codes with
  severity.

### Phase 5 — Combination drills (UI + library)
The first real new UI. Depends on Phases 3–4.
- `data/combination_library.dart` (starter set §14); combination detail screen;
  instructional video plumbing; expected-vs-detected comparison; per-attempt +
  aggregate result (§15).
- **Done when:** user selects a combo, watches an example, performs reps, and sees
  detected attempts + score (acceptance criterion §34).

### Phase 6 — Advanced AI coach schema
Tightens the existing AI layer rather than adding one.
- Strict structured input (§17) — feed CV metrics + selected frames, not prose.
- Strict structured output (§18) — validated schema, not free-text parsing.
- Route low-confidence observations here (§12).
- **Done when:** AI output validates against a schema and is grounded in the CV
  metrics; unschematic output is rejected, not shown.

### Phase 7 — Analytics + validation
- V2 analytics events (§23); track usage, failure rate, combo-classification
  accuracy; begin the labelled regression dataset (§26).

## Deferred (brief §33 LATER)
Uppercut classification if unreliable, slips/rolls/pivots as first-class events,
sparring analysis, multi-person / multi-camera. Domain event model (§20) stays
punch-only for V2; `STEP/SLIP/ROLL/PIVOT` are reserved, not implemented.

## Testing spine (§26, applies throughout)
Every phase adds to: punch grouping, combination matching, timing windows,
threshold logic, score calculation, AI-schema validation — plus fixture-based
synthetic landmark sequences per new detector. The existing `golden_*` tests are
the regression floor and must stay green.
