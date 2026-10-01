# Sparring mode — assessment and plan

Status: **proposal**, nothing built. Written against `main` at #52 (Full AI
review findings); the technique-checkpoint work in #53 is referenced where it
matters.

## Requirements (confirmed)

1. **Both fighters are tracked and analysed** — not just the user.
2. **Identity must be right.** Fighter A must stay fighter A for the whole
   round — through circling, crossovers and clinches. A punch, a stat or a
   correction must never be attributed to the wrong person.
3. **A separate pipeline.** Shadow boxing, combination drills, imported rounds
   and full sessions stay **exactly as they are**: no behaviour change, no
   shared code edited for sparring's sake. Sparring gets its own capture,
   pose extraction, tracking, analysis, storage, sync, AI review and screens.

## Summary

Today the whole pipeline is built for **one person**, from the native plugin
to the review screen:

1. **The native pose plugin asks MediaPipe for one pose and keeps only the
   first.** Android `setNumPoses(1)` + `poses[0]`; iOS `numPoses = 1` +
   `landmarks.first`. A second fighter is ignored, and when tracking is lost
   (a crossover, a clinch) the one pose returned can jump to the other fighter
   mid-round without anything downstream noticing.
2. **Every data type downstream holds one body per frame** (`RawPoseFrame`,
   `PoseFrame`, `PoseSequence`), and every analyser (`AnalysisContext`, body
   scale, punch detection, rules, combinations, checkpoints) runs over that one
   sequence.
3. **The rules are calibrated for a fighter facing the camera.** Sparring is
   filmed side-on: both fighters in profile. Some measures stay valid (punch
   reach, guard height, rotation in-plane); others go blind (head movement is
   measured as *lateral* nose spread — in profile a slip moves the head toward
   or away from the lens, which a single camera barely sees).

Rather than widen that pipeline, sparring is built **alongside it**: a new
native package that extracts every pose per frame, a new tracker that
resolves identity over the **whole round** (it's a recorded clip, so future
frames are available — far more reliable than live tracking), and a sparring
module that analyses each fighter's track by *calling* the existing pure
analysis code with sparring-specific settings, without editing it.

**Recommendation:** AI-led, pose-assisted. Pose does what it's reliable at —
both fighters' identity, output, punch mix, distance, guard height, timing —
and the Full AI review judges what one 2D camera can't (landed punches,
defence quality, decisions), told exactly who is who. Start with a
**3–4 day spike on real sparring footage** with an identity-accuracy gate
before any product work.

## Isolation: a separate pipeline

```
                ┌─────────────── existing (unchanged) ───────────────┐
 shadow / drill │ RoundCaptureScreen → pose_landmarker (1 pose) →     │
 import/session │ PoseSequence → PoseOnlyAdapter → RoundAnalysis →    │
                │ AnalysisStore / ClipStore → BackgroundAnalysis →    │
                │ RoundCoach → round_sync → History                   │
                └─────────────────────────────────────────────────────┘

                ┌─────────────────── sparring (new) ──────────────────┐
 sparring       │ SparringCaptureScreen → sparring_pose (all poses +  │
                │ appearance) → FighterTracker (tracklets → 2 ids) →  │
                │ per-fighter PoseSequence ─┬→ SparringAnalyzer       │
                │                           └→ (calls the existing    │
                │                              rule engine read-only) │
                │ → SparringStore → SparringJobs → SparringCoach →    │
                │ sparring_sync → Sparring history                    │
                └─────────────────────────────────────────────────────┘
```

**Rules of the separation**

- **New code lives in its own places:** `app/packages/sparring_pose/` (native),
  `app/lib/sparring/` (Dart: models, tracker, analysis, stores, jobs, AI,
  sync, UI), `supabase/functions/sparring/`, `supabase/migrations/*_sparring*.sql`.
- **Existing code may be *used*, never *changed*, for sparring.** Pure,
  stateless pieces are called with sparring's own parameters: `PoseSequence`,
  `geometry.dart`, `PunchDetector`, `RuleEngine(rules)` with sparring-chosen
  rule instances and configs, `AnalysisContext(styleProfile: …)` with a
  sparring-only profile, `KeepAwake`, `AppForeground`, `AnalysisProgressCard`,
  the proxy's Gemini helpers (`video.ts`, imported read-only). Where sparring
  needs different behaviour, it gets its own class in `lib/sparring/` — no
  flags or branches added to shared code.
- **Not reused** (they encode the single-person pipeline): `pose_landmarker`
  plugin, `MediaPipePoseEstimator`, `PoseOnlyAdapter`, `RoundAnalysis`,
  `RoundClip`, `ClipStore`, `AnalysisStore`, `BackgroundAnalysis`,
  `RoundCoach`/`AiReview`, `round_sync`/`BackfillQueue`, `SessionType`,
  `SessionRecord`, the `analyze` edge function.
- **The only edits outside the sparring folders** are the entry points:
  a Sparring section on the home screen, a Sparring tab in History,
  `pubspec.yaml` (the new package), `main.dart` only if a route needs
  registering, and docs.
- **Guarded in CI:** the existing test suite (goldens, analyzer, prompt,
  screen tests) must pass untouched, and a CI check fails a sparring PR that
  modifies files outside the allowed list above.

**Cost of the separation:** some duplication — chiefly the native video
decode loop (MediaCodec/AVFoundation, ~200 lines per platform) copied into
`sparring_pose`. Accepted on purpose: it means sparring work can never break
the shipping pose path. Consolidating later is an option, not a requirement.

## What sparring feedback should cover

| Area | Examples | Pose can measure | Needs AI / not measurable in 2D |
| --- | --- | --- | --- |
| Each fighter's technique | guard height, hand return, balance, punch mix | ✅ per fighter (side-view-valid rules only) | — |
| Output | punches thrown per minute per fighter; work-rate share | ✅ | — |
| Distance | time at long / mid / inside range; who closes, who backs up | ✅ hip-centre separation in body-lengths | ring position (no ring model) |
| Exchanges | who starts, who finishes, length | ✅ timing of both fighters' punches | who "won" it |
| Counters | punches within ~0.6 s of the other's | ✅ timing | quality |
| Defence | slip / roll / block / parry / step back in response | ⚠️ partial (rolls, step-backs, guard raise; slips are mostly depth side-on) | ✅ |
| Punch-and-stay | head still after own combination while the other fires back | ⚠️ in-plane only | ✅ |
| Guard under fire | guard height while the other punches | ✅ | — |
| Landed punches | | ❌ 2D overlap ≠ contact (depth ambiguity) | ✅ |
| Tendencies | "kept landing the right over the jab" | ⚠️ patterns from punch types | ✅ |

## Where the single-person assumption lives (and what sparring does instead)

| Layer | Existing (stays as is) | Sparring replacement |
| --- | --- | --- |
| Native pose | `pose_landmarker`: Android `setNumPoses(1)` + `poses[0]`; iOS `numPoses = 1` + `landmarks.first` | `sparring_pose`: `numPoses = 2`, every pose serialised with presence score, bounding box and an appearance descriptor (below) |
| Wire format | `{i, t, lm}` — one body | `{i, t, poses: [{lm, score, box, app}]}` |
| Pose types | `PoseFrame`, `PoseSequence` — one person | `MultiPoseFrame` (unordered candidates) → `FighterTracker` → one existing `PoseSequence` **per fighter** (with gaps where the fighter wasn't resolvable) |
| Estimator service | `MediaPipePoseEstimator` → one sequence | `SparringPoseExtractor` → `TrackedRound` |
| Analysis | `PoseOnlyAdapter` (front-on thresholds, drills, checkpoints) | `SparringAnalyzer`: per-fighter technique via `RuleEngine` with side-view-valid rules + configs and a sparring `StyleProfile`; interaction metrics over both fighters |
| Rule geometry | `head_movement` (lateral nose spread), parts of `footwork`, `body_lean` tuned front-on | not run in sparring until re-validated side-on; sparring-specific rules in `lib/sparring/rules/` where needed |
| Capture | portrait, 720p, `RoundCaptureScreen` | `SparringCaptureScreen`: landscape, 1080p, rounds + rest timer, two-person framing guidance |
| Session model | `SessionType`, `SessionRecord`, `RoundClip` | `SparringSession`, `SparringRound`, `SparringClip` |
| Storage | `ClipStore`, `AnalysisStore` | `SparringClipStore` (own retention), `SparringStore` (tracks, analysis, identity decisions) |
| Background jobs | `BackgroundAnalysis` | `SparringJobs` (same keep-awake / progress patterns, own state) |
| AI review | `RoundCoach`, `CoachingPrompt`, `AiReview`; `analyze` edge function | `SparringCoach`, sparring prompt + schema; `sparring` edge function reusing `video.ts` |
| Sync | `round_sync`, `BackfillQueue`, `analyses` / `keyframes` / `pose` bucket | `sparring_sync` + own queue; `sparring_sessions` / `sparring_rounds` / `sparring_fighters` tables; `sparring` bucket |
| Review UI | one skeleton; `RoundReviewScreen`; History cards | `SparringReviewScreen`: two colour-coded skeletons, per-fighter tabs, exchanges; Sparring tab in History |
| Python reference | legacy `mp.solutions.pose` (single-person by design) | none; sparring is Dart-first. Evaluation tools in `evaluation/sparring/` |
| Evaluation | single-fighter labels, CoachMe front-on | identity labels + per-fighter faults + interaction events on own footage |

## Tracking both fighters correctly

This is the core of the feature and gets the most engineering. The
advantage: rounds are **recorded**, so tracking runs offline over the whole
clip, using frames both before and after any ambiguity.

### Why naive tracking fails

MediaPipe returns up to two bodies per frame **in no guaranteed order and with
no identity**. Matching each frame to the previous one by position works
while the fighters are apart, and fails exactly when it matters: when they
cross (circling, pivots), when one occludes the other, and in clinches, where
the detector can merge two bodies into one skeleton or swap limbs between them.

### Design: tracklets, then identities

1. **Extract every candidate with evidence.** Per frame, per detected body:
   33 landmarks, presence score, bounding box, and an **appearance
   descriptor** computed natively during the same decode pass (no second
   decode): colour histograms of the torso and shorts regions, which the pose
   tells us where to sample. Shorts and top colours are the strongest
   identity cue in a boxing gym.
2. **Reject corrupt poses.** A candidate is dropped when its skeleton is
   implausible: bone lengths far from that fighter's running median, left/right
   limbs crossed in a way bodies can't, too few visible landmarks. This is what
   catches merged-skeleton clinch frames.
3. **Build tracklets.** Link candidates frame to frame only while it's
   unambiguous: predicted position (constant velocity on hip centre and box),
   box overlap and appearance distance, as a 2 × 2 assignment with a strict
   gate. A tracklet **ends** — rather than guesses — when boxes overlap
   heavily, a body drops out for more than a few frames, or the assignment
   margin is small. A round becomes a few dozen clean tracklets.
4. **Link tracklets into the two fighters, over the whole round.** Each
   tracklet is labelled A or B to maximise agreement of appearance (colour
   histograms), body shape (scale-free limb-length ratios: forearm/upper arm,
   shin/thigh, shoulder width/torso) and spatial-temporal continuity (where
   each fighter was just before and after the gap). With two identities this
   is a binary labelling solved exactly (min-cut / dynamic programming over
   time), and every link gets a **margin** = how much better the chosen
   labelling is than swapping it.
5. **Cross-check with facing.** Side-on, each fighter faces the other; a
   change in who is on the left without the facing directions flipping is a
   swap signal.
6. **Mark what can't be resolved.** Frames where neither fighter can be
   assigned with confidence (deep clinch) are **ambiguous**: excluded from
   every metric, punch count and finding, and reported ("12 s of clinch not
   analysed").

### Making sure it's right

- **Confirm who's who.** After round 1 the user taps "which one is you" on a
  clear frame with both skeletons. That picks the label; later rounds of the
  session re-identify by appearance + shape and ask only if unsure.
- **Review uncertain links.** Any link below the margin threshold is shown
  after analysis: two or three thumbnails with colour-coded skeletons around
  the gap, and a "swap" button. Re-running the metrics afterwards is cheap —
  the tracks are stored, nothing is re-extracted.
- **Never guess silently.** A punch, exchange or finding inside an ambiguous
  window is dropped, not attributed.
- **The AI is told who is who.** The sparring prompt identifies both fighters
  by appearance *and* a bounding-box track for each (normalised, 2 Hz), so it
  can't mix them up through crossovers either.

### Targets and validation

| Metric | Target |
| --- | --- |
| Identity switches after user confirmation | **0** per round |
| Automatic identity accuracy (IDF1) on non-ambiguous frames | ≥ 98% |
| Frames marked ambiguous (non-clinch sparring) | ≤ 5% |
| Punches attributed to the wrong fighter (labelled set) | 0 |

Measured on a labelled set of own sparring rounds: identity labelled at 1 Hz
with a small labelling tool in `evaluation/sparring/`. Recorded multi-pose
dumps of real rounds (crossovers, clinches) plus synthetic crossings become
**regression fixtures** for the tracker in CI, the way the shadow pipeline has
its goldens.

## The other hard problems

### Side-on camera geometry

Front-on shadow boxing shows slips as lateral head movement and stance width
as left-right foot spread; side-on both become depth. Sparring needs a
**facing classifier** per fighter, a **sparring style profile** (its own, in
`lib/sparring/`) that runs only rules valid in profile — `guard_return`,
`hands_up`, in-plane rotation, punch detection, balance — and re-calibration of
those thresholds on own sparring footage.

### Landed punches

In 2D a fist overlapping the other fighter's head is as likely 30 cm in front
of it. Pose can only say "a punch peaked near the head/body" (**candidate**);
whether it landed is the AI review's call (it sees the reaction). Reported as
the AI's estimate, never as a measured count.

### Defensive events

The combination library already defers slips/rolls to "their own event model"
(COMBINATIONS.md → Not yet). Sparring needs it: an event = one fighter's
punch → the other's response within ~300 ms (guard raise, roll = head drops,
step back = hip centre retreats, slip = head displacement, mostly depth side-on).
Pose grades the in-plane ones; the AI grades the rest.

### Compute on the phone

Today a 2-minute round (3,601 frames at 33 ms) takes ~200 s on Grant's phone
(~55 ms/frame, CPU — the GPU delegate is disabled because it crashes on some
devices). Two bodies roughly double the landmark work, the appearance
descriptor adds a little, and the **full** model is preferable to lite for two
smaller figures. Estimate for a 3-minute round: ~5–8 min at 20 fps.
Mitigations: sample sparring at **20 fps** (tracking continuity suffers below
that), analyse each round in the background **during the rest minute**, and
revisit the GPU delegate on a device allow-list. The tracker itself is cheap.

### Consent and privacy

Both fighters are filmed, measured and stored, and in the AI modes the video is
uploaded to Google. Needed before shipping:

- a **consent step** in sparring setup ("My sparring partner agreed to be
  filmed and analysed"), stored with the session;
- without consent: AI review off for that session, the partner's track not
  stored or synced (their metrics shown once, then discarded);
- privacy policy + Play **Data safety** updates (data about people other than
  the user), and account deletion covering sparring data.

### AI context and cost

On current Gemini models video defaults to **low media resolution, ~66–70
tokens per frame**. A 3-minute round at 24 fps ≈ 4,300 frames ≈ **0.3 M
tokens**, well inside a 1 M context; one request per round (a 3 × 3 session at
once would be ~0.9 M, too close). Roughly **$0.09 per round** on Flash-Lite
input, $0.23–0.45 on Flash. Whether it draws on the same weekly quota is a
decision below.

## Proposed design

### Capture

- **Sparring** on the home screen → setup: rounds (default 3), length
  (2–3 min), rest (1 min), names/colours for the two fighters (optional, helps
  the AI), partner consent.
- `SparringCaptureScreen`: **landscape**, **1080p**, placement guidance
  (ring-side, ~waist height, far enough that both stay head-to-feet in frame
  while moving), rest timer between rounds, one `SparringClip` per round.
- Each round's extraction + tracking starts in the background as soon as it
  ends (`SparringJobs`).

### Pose extraction and tracking

- `sparring_pose` package: `numPoses = 2`, full model, 20 fps sampling, emits
  `MultiPoseFrame`s with landmarks, score, box and appearance descriptor.
- `lib/sparring/tracking/`: `TrackletBuilder`, `IdentityLinker`,
  `FighterTracker` → `TrackedRound { fighters: {A, B} → PoseSequence,
  ambiguous: frame ranges, links: [{at, margin, decision}] }`.
- Identity decisions (user tap, swaps) stored with the round in `SparringStore`.

### Analysis

- **Each fighter:** `RuleEngine` with the side-view-valid rules and the
  sparring `StyleProfile`, over that fighter's `PoseSequence` → technique
  observations, punch list, punch mix. Labelled **You** and **Partner** (or
  names).
- **Interaction** (`lib/sparring/analysis/interaction.dart`): distance
  timeline and range bands, output per fighter, exchanges, counters, guard
  under fire, punch-and-stay candidates, landed **candidates**, all excluding
  ambiguous windows.
- Result: `SparringRoundAnalysis { fighters: {A, B} → FighterAnalysis,
  interaction, exchanges, ambiguousSeconds }`.

### AI review

- `SparringCoach` + sparring prompt: both fighters identified by description
  and per-fighter box tracks; the measurements for both and the interaction
  metrics as JSON; the tracker's ambiguous windows flagged.
- Schema: findings **per fighter** (same shape as today's, plus `fighter`),
  `exchanges` (start, end, who started, summary), `defence` (sampled attacks:
  response, verdict), `landed_estimate` per fighter, `patterns` per fighter.
- `supabase/functions/sparring/`: upload + generate routes reusing `video.ts`
  (read-only import), its own quota accounting if the decision below is
  "separate".

### Data and sync

- `SparringStore` (on device): clip, per-fighter `pose.json`, `tracked.json`
  (tracklets + links), `analysis.json`, identity decisions.
- Supabase (new migration): `sparring_sessions`, `sparring_rounds`,
  `sparring_fighters` (per-round, per-fighter metrics; the partner's row only
  with consent), keyframes in a `sparring` bucket; RLS as the existing tables.
- Own sync queue (`sparring_sync`), same durability pattern as `BackfillQueue`
  but separate state.

### UI

- `SparringReviewScreen`: video with both skeletons (user accent, partner
  muted, toggle each), per-fighter tabs (technique, output, punch mix), an
  interaction panel (range split, exchanges, counters), exchanges and findings
  as moments, and "Check who's who" when a link was uncertain.
- History: a **Sparring** tab listing sparring sessions from `SparringStore` /
  `sparring_sessions` — the existing session list is untouched.

## What does not change

Everything in the existing pipeline: `pose_landmarker`, `PoseOnlyAdapter`,
rules and their thresholds, combinations and checkpoints, `RoundAnalysis`,
`RoundClip`, `ClipStore`, `AnalysisStore`, `BackgroundAnalysis`,
`RoundCoach` / `AiReview`, the `analyze` function, `round_sync`, `SessionType`,
the session engine and templates, the review screen, the existing History list
and progress stats.

## Phasing

Estimates are focused development days, rough.

| Phase | Scope | Est. | Gate / output |
| --- | --- | --- | --- |
| **0 · Spike** | `sparring_pose` prototype (2 poses + boxes + appearance) on Android; tracklets + linking prototype; 5 real sparring rounds (landscape, 1080p) labelled for identity | 3–4 | IDF1 ≥ 98% on non-ambiguous frames, ≤ 1 swap per round before confirmation, ≤ 5% ambiguous outside clinches, extraction ≤ 3× real time. **Go / no-go** |
| **1 · Pipeline + tracking** | `sparring_pose` (Android + iOS), `FighterTracker` with tests and recorded fixtures, `SparringCaptureScreen`, consent, `SparringStore`, `SparringJobs`, "which one is you", "check who's who", per-fighter technique, two-skeleton review, CI isolation check | 12–16 | Both fighters tracked and analysed, identity confirmed |
| **2 · AI sparring review** | `SparringCoach`, prompt + schema, `sparring` edge function, per-fighter findings, exchanges/defence/landed estimates | 4–6 | Full AI review of a round, about the right fighter |
| **3 · Interaction + history + sync** | distance, output, exchanges, counters, guard under fire; Sparring tab; migration + `sparring_sync` | 6–9 | Measured sparring stats per round and session, synced |
| **4 · Defence events + evaluation** | defensive event model, landed candidates, labelled sparring set, threshold calibration | 10+ | Calibrated, evaluated sparring analysis |

Phase 2 can ship before Phase 3: with tracking in place, the AI review alone
gives useful sparring feedback for both fighters.

## Decisions needed

1. **AI quota.** Does a sparring round draw on the same weekly AI allowance
   (a 3 × 3 session = 3 analyses), or its own?
2. **Partner feedback.** Show the partner full technique corrections, or only
   their stats (output, punch mix, guard) — they're not the one who asked?
3. **Partner data without consent.** Recommended: analyse once on-device,
   show, then discard (nothing stored or uploaded, AI off).
4. **Identity UX.** One tap after round 1 + "check who's who" on uncertain
   links (recommended), vs asking fighters to start on fixed sides.
5. **Camera.** One phone, side-on, landscape (recommended); a second phone is
   the multi-camera roadmap, not this.

## Risks

- **Identity in long clinches** — mitigated by ending tracklets and relinking
  after separation, not solved during the clinch; clinch-heavy rounds yield
  less measured data (reported, not guessed).
- **Similar kit** — two fighters in the same colours weaken the appearance
  cue; body shape and continuity carry it, and uncertain links go to the user.
  Setup can suggest different colours.
- **Small figures in frame** — two full bodies in landscape are about half the
  pixel height of one front-on fighter in portrait; landmark jitter rises.
  1080p and the full model help; the spike measures it.
- **Compute and battery** — minutes per round; the rest minute absorbs part.
- **Rule validity side-on** — the sparring profile runs only rules
  re-validated in profile.
- **Duplication** — the copied native decode loop must get any important fix
  in both places until (optionally) consolidated.
- **Privacy** — partner consent and data-safety changes are a launch
  requirement.

## Sources

- Gemini video understanding — frame rate, default (low) media resolution and
  tokens per frame: <https://ai.google.dev/gemini-api/docs/video-understanding>
- Gemini media resolution token table:
  <https://ai.google.dev/gemini-api/docs/media-resolution>
- Gemini pricing: <https://ai.google.dev/gemini-api/docs/pricing>
