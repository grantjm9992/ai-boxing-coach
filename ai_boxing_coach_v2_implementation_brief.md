# AI Boxing Coach — V2 Implementation Brief

## 0. Purpose of This Document

This document defines the next version of the AI Boxing Coach app and is intended to be used directly by an AI coding agent.

The goal of V2 is to move the product from a basic boxing-analysis prototype toward a more credible, boxing-specific coaching product before wider public marketing.

The main competitive requirement is:

> The app must provide more specific, more boxing-aware, and more useful technical feedback than generic “AI martial arts” competitors.

The product should remain boxing-first.

## 1. V2 Product Goals

V2 should add five major capabilities:

1. **Refine technical analysis**
   - Add more detailed body-mechanics observations.
   - Include leaning, rotation, body position and footwork.

2. **Support shadow boxing**
   - Analysis should work without a bag.
   - Shadow-boxing sessions should be a first-class training mode.

3. **Add simple structured rounds**
   - Shadow-boxing rounds.
   - Technical-work rounds.
   - User can select what kind of session they are performing.

4. **Detect and analyse combinations**
   - Identify individual punch types.
   - Identify punch sequences such as 1-2, 1-2-3, 1-3-4.
   - Analyse execution of the full combination, not only each punch independently.

5. **Add combination instruction videos**
   - User can select a combination.
   - App shows the combination visually.
   - User performs it.
   - App analyses whether the expected sequence was actually thrown and how well it was executed.

## 2. Key Architectural Decision

### Do NOT use the large multimodal AI model for everything

V2 should use a **hybrid analysis architecture**.

### Deterministic / CV layer

Use pose estimation, tracked landmarks, timing and movement heuristics for measurements that should be objective.

Examples:

- hand positions
- elbow positions
- shoulder positions
- hip positions
- foot positions
- stance width
- body lean
- torso rotation
- punch extension
- punch recovery
- guard position
- punch classification
- punch timing
- combination sequencing
- balance
- foot movement

### AI reasoning layer

Use the larger AI/VLM model for:

- interpreting measurements
- identifying broader technical patterns
- explaining why an error matters
- combining several observations into coaching feedback
- summarising a round
- prioritising the most important issues
- analysing ambiguous sequences
- generating human-readable coaching advice

### Principle

```text
Video
↓
Pose / motion tracking
↓
Deterministic boxing metrics
↓
Punch + combination detection
↓
Structured analysis data
↓
AI coaching/reasoning layer
↓
User-facing coaching report
```

The AI model should not be asked to estimate every angle or identify every punch directly from raw video if deterministic data can do it more reliably.

## 3. Full AI Mode — When It Is Needed

### Full AI mode IS useful for:

- overall round analysis
- interpreting multiple technical faults together
- explaining patterns
- recognising nuanced boxing context
- generating useful coaching advice
- comparing behaviour early vs late in a round
- interpreting uncertain combinations
- analysing unusual movement that does not fit simple heuristics

### Full AI mode is NOT required for:

- calculating body lean
- measuring shoulder rotation
- checking stance width
- detecting whether a hand drops below a threshold
- determining whether a foot moved
- timing punch recovery
- sequencing classified punches into `1-2-3`
- measuring whether the user returned to guard

These should normally come from pose/motion analysis.

### Recommended execution modes

#### Standard Analysis

```text
Video
→ pose/CV
→ metrics
→ rules
→ concise feedback
```

#### Advanced AI Analysis

```text
Video
→ pose/CV
→ metrics
→ relevant clips/frames
→ large AI/VLM
→ richer coaching report
```

This distinction can later become part of the Free vs Pro product.

## 4. Session Types

Add a `session_type` concept.

Suggested enum:

```text
SHADOW_BOXING
HEAVY_BAG
TECHNICAL_WORK
COMBINATION_DRILL
FREE_TRAINING
```

Every analysis should know the session type.

Different session types should use different expectations and thresholds.

## 5. Shadow Boxing Mode

### Goal

Allow the user to perform full shadow-boxing rounds and receive useful analysis.

### Requirements

- User selects `Shadow Boxing`.
- App records the round.
- Full body should ideally remain visible.
- Analyse guard, stance, punch mechanics, recovery, body position, rotation, leaning, footwork, balance and repeated technical errors.

### Shadow Boxing Report

```json
{
  "session_type": "SHADOW_BOXING",
  "duration_seconds": 180,
  "punch_count": 0,
  "combinations_detected": [],
  "strengths": [],
  "issues": [],
  "round_summary": "",
  "priority_correction": ""
}
```

## 6. Technical Work Mode

### Goal

Allow a user to deliberately work on one technique rather than completing a generic round.

Examples:

- jab
- right cross
- lead hook
- rear hook
- 1-2
- 1-2-3
- slips
- pivots
- guard recovery

### Flow

```text
Choose Technical Work
↓
Choose technique / combination
↓
Watch optional example
↓
Record attempts
↓
Detect attempts
↓
Analyse each attempt
↓
Aggregate feedback
```

## 7. Punch Numbering System

Use conventional boxing numbering, but keep it configurable because numbering conventions can vary.

Initial default:

```text
1 = Jab
2 = Rear Straight / Cross
3 = Lead Hook
4 = Rear Hook
5 = Lead Uppercut
6 = Rear Uppercut
```

Store the semantic punch type separately from the number.

## 8. Punch Classification

Implement punch-event detection.

### Initial punch types

```text
JAB
CROSS
LEAD_HOOK
REAR_HOOK
LEAD_UPPERCUT
REAR_UPPERCUT
UNKNOWN
```

### Punch event object

```json
{
  "id": "punch_001",
  "type": "JAB",
  "number": 1,
  "start_ms": 12200,
  "impact_or_peak_ms": 12450,
  "end_ms": 12720,
  "confidence": 0.91,
  "hand": "LEAD",
  "metrics": {}
}
```

## 9. Combination Detection

Convert individual punch events into meaningful boxing combinations.

Example event stream:

```text
JAB at 12.2s
CROSS at 12.7s
LEAD_HOOK at 13.1s
```

Should produce:

```text
1-2-3
```

Use a configurable maximum gap. Initial starting point:

```text
MAX_COMBINATION_GAP_MS = 1200
```

Tune this through real recordings.

### Combination object

```json
{
  "id": "combo_001",
  "start_ms": 12200,
  "end_ms": 13400,
  "sequence": [1, 2, 3],
  "types": ["JAB", "CROSS", "LEAD_HOOK"],
  "confidence": 0.88,
  "punch_ids": ["punch_001", "punch_002", "punch_003"]
}
```

## 10. Combination Drill Analysis

For a known target combination, return more than simply `matched = true`.

Analyse:

- sequence accuracy
- timing
- rhythm
- hand recovery
- guard between punches
- balance
- stance
- weight transfer
- rotation
- overextension
- final body position

Example:

```json
{
  "expected_sequence": [1, 2, 3],
  "detected_sequence": [1, 2, 3],
  "sequence_match": true,
  "score": 78,
  "issues": [
    {
      "code": "LEAD_HAND_DROPS_AFTER_CROSS",
      "severity": "MEDIUM"
    }
  ]
}
```

## 11. New Technical Analysis Points

### 11.1 Body Lean

Measure torso angle relative to vertical.

Potential observations:

```text
EXCESSIVE_FORWARD_LEAN
EXCESSIVE_BACKWARD_LEAN
EXCESSIVE_LEFT_LEAN
EXCESSIVE_RIGHT_LEAN
```

Store raw measurements where possible and keep thresholds configurable.

### 11.2 Torso / Shoulder Rotation

Measure shoulder-line and hip-line orientation where possible.

Potential issues:

```text
INSUFFICIENT_ROTATION
OVER_ROTATION
ROTATION_TOO_EARLY
ROTATION_TOO_LATE
FAILURE_TO_RECOVER_POSITION
```

2D estimates must carry confidence because camera angle matters.

### 11.3 Body Position

Analyse head relative to hips, shoulders relative to hips, centre-line displacement and posture after punches.

Potential issues:

```text
HEAD_TOO_FAR_FORWARD
HEAD_OVER_FRONT_KNEE
BODY_TOO_UPRIGHT
BODY_POSITION_NOT_RECOVERED
OFF_CENTRE_AFTER_PUNCH
```

### 11.4 Footwork

Track stance width, relative foot positions, movement direction, crossover and stance recovery.

Initial issue codes:

```text
FEET_CROSSING
STANCE_TOO_NARROW
STANCE_TOO_WIDE
FEET_TOO_SQUARE
REAR_FOOT_LAGGING
LEAD_FOOT_LAGGING
STANCE_NOT_RECOVERED
BALANCE_LOST_AFTER_STEP
```

### 11.5 Guard Analysis

Expand guard analysis to track hand height, hand-to-head distance, guard before/during/after punches and recovery time.

Potential issue codes:

```text
LEAD_HAND_LOW
REAR_HAND_LOW
LEAD_HAND_DROPS_DURING_REAR_PUNCH
REAR_HAND_DROPS_DURING_LEAD_PUNCH
SLOW_GUARD_RECOVERY
BOTH_HANDS_LOW
```

### 11.6 Punch Recovery

Measure peak extension to return toward guard.

Potential issues:

```text
SLOW_RECOVERY
HAND_NOT_RETURNED_TO_GUARD
OVEREXTENDED
```

### 11.7 Balance

Use torso/head displacement, stance geometry and corrective steps as signals.

Potential issues:

```text
OFF_BALANCE_AFTER_PUNCH
OFF_BALANCE_AFTER_COMBINATION
EXCESSIVE_WEIGHT_FORWARD
EXCESSIVE_WEIGHT_BACKWARD
CORRECTIVE_STEP_REQUIRED
```

## 12. Analysis Confidence

Every advanced observation should carry confidence.

```json
{
  "code": "INSUFFICIENT_ROTATION",
  "confidence": 0.79,
  "severity": "MEDIUM"
}
```

Low-confidence detections should be omitted or escalated to the AI reasoning layer.

## 13. Camera Quality Gate

Before advanced analysis, validate recording suitability:

- full body visible
- feet visible
- hands visible frequently enough
- sufficient brightness
- user not too far away
- user not too close
- body not heavily cropped

If quality is too low, instruct the user how to improve setup rather than producing confident bad analysis.

## 14. Combination Video Library

Add an instructional combination library.

```json
{
  "id": "combo_123",
  "name": "Jab → Cross → Lead Hook",
  "numbers": [1, 2, 3],
  "punches": ["JAB", "CROSS", "LEAD_HOOK"],
  "difficulty": "BEGINNER",
  "video_url": "...",
  "description": "...",
  "coaching_points": []
}
```

Suggested starter set:

```text
1-2
1-1-2
1-2-3
1-2-3-2
1-3
1-3-2
1-3-4
2-3-2
1-2-5-2
1-2-slip-2
```

Defensive actions should eventually have their own event model rather than pretending every action is a punch.

## 15. Combination UI

Suggested flow:

```text
Combinations
↓
Choose combination
↓
Watch example video
↓
View punch sequence
↓
Start drill
↓
Perform multiple repetitions
↓
See detected attempts
↓
Get score + feedback
```

## 16. Round Types

Add simple round templates.

### Shadow Boxing Round

```text
1 minute
2 minutes
3 minutes
```

### Technical Round

Examples:

```text
Jab only
1-2
Hooks
Footwork
Guard recovery
Selected combination
```

## 17. Advanced AI Analysis Input

The large AI model should receive structured data rather than only raw prose.

```json
{
  "session": {
    "type": "SHADOW_BOXING",
    "duration_seconds": 180
  },
  "capture_quality": {},
  "punches": [],
  "combinations": [],
  "metrics": {
    "guard": {},
    "rotation": {},
    "lean": {},
    "footwork": {},
    "balance": {}
  },
  "detected_issues": []
}
```

Optionally include selected relevant image frames/clips.

## 18. AI Output Schema

Require structured output.

```json
{
  "summary": "Overall technically solid round...",
  "strengths": [],
  "priority_issues": [
    {
      "code": "LEAD_HAND_DROPS_DURING_REAR_PUNCH",
      "severity": "HIGH",
      "confidence": 0.91,
      "timestamps": [12.4, 28.1],
      "observation": "...",
      "why_it_matters": "...",
      "correction": "...",
      "suggested_drill": "..."
    }
  ],
  "combination_feedback": [],
  "next_session_focus": []
}
```

Do not rely on parsing arbitrary natural-language output.

## 19. Analysis Layer Interfaces

Keep layers independently replaceable.

Suggested interfaces:

```text
PoseEstimator
PunchDetector
CombinationDetector
GuardAnalyzer
RotationAnalyzer
LeanAnalyzer
FootworkAnalyzer
BalanceAnalyzer
SessionAnalyzer
AICoach
```

Do not tightly couple model/provider-specific implementation to the boxing domain layer.

## 20. Domain Event Model

Recommended event types:

```text
PUNCH
STEP
SLIP
ROLL
PIVOT
GUARD_CHANGE
STANCE_CHANGE
UNKNOWN
```

V2 must only require punch events, but architecture should allow defensive/movement events later.

## 21. Data Persistence

Persist enough structured analysis to improve the algorithm later:

- session metadata
- analysis version
- pose-derived metrics
- detected events
- combinations
- issue codes
- confidence
- user-visible report

Store an `analysis_version`, e.g.:

```text
analysis_version = "2.0.0"
```

## 22. Feature Flags

Suggested flags:

```text
shadow_boxing_v2
footwork_analysis
rotation_analysis
combination_detection
combination_drills
advanced_ai_analysis
```

## 23. Analytics Events

Add analytics for:

```text
session_started
session_completed
analysis_started
analysis_completed
analysis_failed
shadow_boxing_started
technical_round_started
combination_selected
combination_attempt_detected
combination_match_success
combination_match_failure
advanced_analysis_requested
feedback_viewed
video_example_viewed
```

## 24. V2 UX Priorities

Do not overwhelm users with 20 observations.

Suggested hierarchy:

```text
Overall round
↓
Top 1–3 things to fix
↓
Strengths
↓
Combination analysis
↓
Detailed metrics
```

The product should feel like coaching, not a biomechanics spreadsheet.

## 25. Error Taxonomy

Create stable internal error codes. Do not use display text as identifiers.

Example:

```text
GUARD_001 = LEAD_HAND_LOW
GUARD_002 = REAR_HAND_LOW
ROT_001 = INSUFFICIENT_ROTATION
BAL_001 = OFF_BALANCE_AFTER_PUNCH
FOOT_001 = FEET_CROSSING
```

## 26. Testing Requirements

### Unit tests

Add tests for:

- punch grouping
- combination matching
- timing windows
- issue threshold logic
- score calculation
- AI-output schema validation

### Fixture-based tests

Create known recordings or synthetic landmark sequences representing:

- jab
- cross
- lead hook
- rear hook
- 1-2
- 1-2-3
- 1-3-4
- incorrect sequences
- guard drops
- overextension
- leaning
- foot crossing

### Regression dataset

Begin building a private labelled dataset of real boxing clips.

```json
{
  "video": "test_001.mp4",
  "expected_punches": [1, 2, 3],
  "known_issues": ["LEAD_HAND_DROPS_DURING_REAR_PUNCH"]
}
```

## 27. Scoring

Do not make one arbitrary universal boxing score the foundation of V2.

Prefer component scores where useful:

```text
Guard
Balance
Footwork
Punch Mechanics
Combination Execution
```

Avoid false precision.

## 28. Performance

Analysis should remain asynchronous.

```text
Finish round
↓
Upload
↓
Create analysis job
↓
Show progress
↓
Process pose/CV
↓
Run AI if required
↓
Return report
```

## 29. Cost Control

Do not run advanced AI analysis unnecessarily.

Possible policy:

```text
Basic/free analysis
→ CV + rules

Advanced analysis
→ CV + AI

Ambiguous detection
→ selectively invoke AI
```

For full-round AI, pre-process video, detect relevant events, select important frames/windows and pass structured metrics rather than feeding every raw 30–60 FPS frame to the VLM.

## 30. Self-Hosted AI Direction

Current concrete infrastructure direction:

> Self-host an open multimodal Qwen-family model for advanced analysis.

Current experimentation includes Qwen3.8-class models running through llama.cpp / RunPod infrastructure.

Long-term architecture should not depend on one specific model name. Use an abstraction such as:

```text
AIAnalysisProvider
```

## 31. Privacy / Security

Do not expose AI provider infrastructure directly from the mobile app.

```text
Mobile app
↓
Application backend
↓
Analysis worker / AI infrastructure
```

Do not embed RunPod credentials, model-service secrets or private-storage credentials in the client.

## 32. V2 Delivery Phases

### Phase 1 — Domain + Session Types

- [ ] Add `session_type`.
- [ ] Add shadow boxing.
- [ ] Add technical work.
- [ ] Add round presets.
- [ ] Update data model.

### Phase 2 — Refined Existing Analysis

- [ ] Improve guard analysis.
- [ ] Add body lean.
- [ ] Add body position.
- [ ] Add torso / shoulder rotation.
- [ ] Add balance.
- [ ] Add footwork.
- [ ] Add confidence values.
- [ ] Add recording-quality gate.

### Phase 3 — Punch Detection

- [ ] Define punch event model.
- [ ] Detect jab.
- [ ] Detect cross.
- [ ] Detect lead hook.
- [ ] Detect rear hook.
- [ ] Add uppercuts if reliable.
- [ ] Add punch confidence.
- [ ] Add regression tests.

### Phase 4 — Combination Detection

- [ ] Group punch events.
- [ ] Implement timing thresholds.
- [ ] Produce numbered sequences.
- [ ] Detect 1-2.
- [ ] Detect 1-2-3.
- [ ] Detect 1-3-4.
- [ ] Handle incorrect sequence.
- [ ] Analyse combination execution.

### Phase 5 — Combination Drills

- [ ] Create combination library.
- [ ] Add combination detail screen.
- [ ] Add instructional videos.
- [ ] Allow user to start combination drill.
- [ ] Compare expected vs detected sequence.
- [ ] Show per-attempt feedback.
- [ ] Show aggregate drill result.

### Phase 6 — Advanced AI Coach

- [ ] Define structured AI input schema.
- [ ] Define structured AI output schema.
- [ ] Add AI provider abstraction.
- [ ] Pass CV metrics to model.
- [ ] Optionally pass selected frames.
- [ ] Generate round summary.
- [ ] Generate prioritised issues.
- [ ] Generate suggested corrections.
- [ ] Generate suggested next-session focus.

### Phase 7 — Analytics + Validation

- [ ] Add V2 analytics events.
- [ ] Add feature flags.
- [ ] Track feature usage.
- [ ] Track analysis failure rate.
- [ ] Track combination classification accuracy.
- [ ] Collect user feedback.
- [ ] Build labelled regression dataset.

## 33. MVP Scope for V2

### MUST

- [ ] Shadow-boxing mode.
- [ ] Technical-work mode.
- [ ] Better guard analysis.
- [ ] Body lean.
- [ ] Rotation.
- [ ] Footwork basics.
- [ ] Jab / cross / lead-hook detection.
- [ ] 1-2 detection.
- [ ] 1-2-3 detection.
- [ ] Combination drill structure.
- [ ] Structured AI report.

### SHOULD

- [ ] 1-3-4.
- [ ] Rear hook.
- [ ] Balance metrics.
- [ ] Combination videos.
- [ ] Advanced full-round AI analysis.

### LATER

- [ ] Uppercut classification if unreliable.
- [ ] Slips / rolls / pivots.
- [ ] Sparring-specific analysis.
- [ ] Multi-person tracking.
- [ ] Multi-camera analysis.
- [ ] Hardware integration.

## 34. Acceptance Criteria

V2 is ready for broader validation when:

- User can select shadow boxing, record a full round and receive boxing-specific analysis.
- App provides analysis for guard, lean, rotation, body position and basic footwork.
- System can distinguish at minimum jab, rear straight/cross and lead hook on suitable recordings.
- System can differentiate `1-2-3` from `1-3-4` and from an incorrect/unknown sequence.
- User can select a combination, watch an example, perform it and receive sequence + technique feedback.
- AI output is structured and grounded in deterministic metrics where available.
- The UI prioritises the most important corrections rather than dumping all metrics.

## 35. Important Development Principle

Do not solve the problem by continually adding more prompt text.

Where a feature can be measured from pose/motion data, implement it as a measurable domain concept.

Use AI to **reason over evidence**, not to replace evidence.

## 36. Product Principle

V2 should make the app feel:

> **Built by people who understand boxing.**

Not:

> **A generic vision model with “boxing coach” in the prompt.**

That distinction is the competitive advantage this version should create.
