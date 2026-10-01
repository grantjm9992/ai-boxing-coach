# Sparring mode — assessment and plan

Status: **proposal**, nothing built. Written against `main` at #52 (Full AI
review findings); the technique-checkpoint work in #53 is referenced where it
matters.

## Summary

Yes — the whole pipeline is built for **one person**, and the assumption runs
from the native plugin to the review screen:

1. **The native pose plugin asks MediaPipe for one pose and keeps only the
   first.** Android `setNumPoses(1)` + `poses[0]`; iOS `numPoses = 1` +
   `landmarks.first`. A second fighter in frame is ignored, and when tracking
   is lost (a crossover, a clinch) the one pose returned can jump to the other
   fighter mid-round without anything downstream noticing.
2. **Every data type downstream holds one body per frame** (`RawPoseFrame`,
   `PoseFrame`, `PoseSequence`), and every analyser (`AnalysisContext`, body
   scale, punch detection, rules, combinations, checkpoints) runs over that one
   sequence.
3. **The rules are calibrated for a fighter facing the camera.** Sparring is
   filmed side-on: both fighters in profile. Some measures stay valid (punch
   reach, guard height, rotation in-plane); others go blind (head movement is
   measured as *lateral* nose spread — in profile a slip moves the head toward
   or away from the lens, which a single camera barely sees).

Making sparring work is mostly not about the engine; it's three new problems:
**knowing who is who** across a round (tracking + picking out the user),
**measuring the interaction** between two fighters (distance, exchanges,
counters, defence), and **consent**, because the partner is filmed, measured
and — in the AI modes — uploaded.

**Recommendation:** run sparring **AI-led, pose-assisted**. Pose does what it's
reliable at — finding both fighters, tracking who is who, output, distance,
guard height, timing — and the Full AI review judges what a single 2D camera
can't (landed punches, defence quality, decisions), told exactly which fighter
is the user. Start with a **2–3 day spike on real sparring footage** that
decides go/no-go before any product work.

## What sparring feedback should cover

The user's own technique under pressure (guard, retraction, balance —
the existing engine), plus what only sparring has:

| Area | Examples | Pose can measure | Needs AI / not measurable in 2D |
| --- | --- | --- | --- |
| Output | punches thrown per minute, per fighter; work-rate share | ✅ per track | — |
| Distance | time at long / mid / inside range; who closes, who backs up | ✅ hip-centre separation in body-lengths | ring position (no ring model) |
| Exchanges | who starts, who finishes, length | ✅ timing of both fighters' punches | who "won" it |
| Counters | user punches within ~0.6 s of the partner's | ✅ timing | quality |
| Defence | slip / roll / block / parry / step back in response | ⚠️ partial (rolls, step-backs, guard raise; slips are mostly depth in side view) | ✅ |
| Punch-and-stay | user's head still after their own combination while the partner fires back | ⚠️ head displacement in-plane only | ✅ |
| Guard under fire | user's guard height while the partner punches | ✅ | — |
| Landed punches | | ❌ 2D overlap ≠ contact (depth ambiguity) | ✅ |
| Partner tendencies | "kept landing the right over your jab" | ⚠️ patterns from punch types | ✅ |

## Where the single-person assumption lives

| Layer | Where | Today | Change |
| --- | --- | --- | --- |
| Native pose (Android) | `pose_landmarker/android/…/PoseLandmarkerPlugin.kt` `createLandmarker`, `frameToMap` | `setNumPoses(1)`; serialises `poses[0]` only | `numPoses` from the call args (1 default, 2 for sparring); serialise every pose with its presence score |
| Native pose (iOS) | `pose_landmarker/ios/Classes/PoseLandmarkerPlugin.swift` | `options.numPoses = 1`; `result.landmarks.first` | same as Android |
| Wire format | `pose_landmarker/lib/pose_landmarker.dart` `RawPoseFrame` | `{i, t, lm: [33 × 4]}` | add `poses: [{lm, score}]`; keep `lm` (= first pose) so old builds/tools still parse |
| Dart pose types | `analysis/pose.dart`, `analysis/pose_estimation.dart` | `PoseFrame` = one `keypoints` map; `PoseSequence` = one person | keep both **unchanged as the per-person type**; add `MultiPoseFrame` (unordered poses) → tracker → one `PoseSequence` per track |
| Estimator service | `services/pose_estimator.dart` | yields one `PoseSequence` | `analyseMulti(...)` yielding a `TrackedRound` (tracks + ambiguous frames) |
| Analysis engine | `analysis/context.dart`, `features.dart`, `rules/*`, `combination*.dart`, `pose_only_adapter.dart` | one sequence; body scale = median torso of "the" person | **no structural change** — run it on the user's track. Add a side-view style profile for sparring (below) |
| Rule geometry | `rules/head_movement.dart` (lateral nose spread), `rules/footwork.dart`, `rules/body_lean.dart`, … | thresholds tuned for a front-on camera | a `SessionType.sparring` / side-view profile that disables or re-tunes rules blind in profile; a per-track view classifier (facing left / right / camera) |
| Capture | `main.dart` orientation lock, `camera_round_recorder.dart` (`ResolutionPreset.high` = 720p), `round_capture_screen.dart`, `camera_check_screen.dart` | portrait only, 720p, "get your whole body in frame" | landscape for sparring (two bodies side by side), 1080p (each fighter is smaller in frame), two-person framing guidance |
| Session model | `analysis/session_type.dart` | no sparring type | `SessionType.sparring` (`SPARRING`) + a multi-round template (rounds × length + rest) |
| AI review | `services/ai/coaching_prompt.dart`, `round_coach.dart`, `analysis/ai_review.dart` | prompts say "the fighter"; nothing tells the model which person to judge | a sparring prompt + schema that identifies the user (description + box track) and adds exchanges/defence; findings stay the same shape so `AiReview` and moments reuse |
| Storage & sync | `services/analysis_store.dart`, `services/sync/round_sync.dart`, Supabase `analyses` / `pose` bucket | one `pose.json` and one analysis per round | user track always; partner track only with consent; a `sparring` JSON block (interaction metrics, exchanges) on the analysis row or its own table |
| Review UI | `ui/widgets/skeleton_painter.dart`, `round_review_screen.dart`, History cards | one skeleton | two skeletons (user in accent, partner grey), a sparring summary card (output, range, exchanges, counters) |
| Python reference | `src/boxing_coach/pose_estimation/mediapipe_estimator.py` | legacy `mp.solutions.pose` — **single-person by design** | only if parity is wanted: move to the Tasks `PoseLandmarker` with `num_poses`. Recommend sparring stays **Dart-first** (as the V2 additions are) |
| Evaluation | `annotations/schemas/ground_truth.schema.json`, CoachMe dataset | `exercise` enum has no sparring; labels are per single fighter; CoachMe is single-person | `exercise: sparring`, labels keyed by fighter, interaction events; a small own-footage sparring set |

## The hard problems

### A. Who is who (tracking + picking out the user)

MediaPipe returns up to `numPoses` bodies per frame **in no guaranteed order and
with no identity**. A tracker has to stitch them into two consistent people:

- **Frame-to-frame assignment.** With two people it's a 2×2 choice: keep or swap,
  whichever minimises torso-centre distance + bounding-box overlap change from
  the previous frame. Pure Dart, unit-testable on synthetic crossings.
- **Crossovers and clinches.** Fighters circle and swap sides; in a clinch the
  bodies overlap and MediaPipe merges or swaps limbs. Frames where the two
  bodies' boxes overlap heavily, or one pose drops out, are marked
  **ambiguous** and excluded from metrics; identity is re-established after
  separation with a **signature**: body proportions (height, torso length,
  shoulder width in body-scale units) and, if needed, shorts/top colour sampled
  from a few grabbed frames (`FrameGrabber` already exists).
- **Which one is the user.** Cheapest reliable UX: after the first round's
  analysis, show a clear frame with both skeletons and ask **"Which one is
  you?"** (one tap); later rounds of the same session re-identify by signature
  and confirm only if unsure. Alternative before recording: "start on the left".

### B. Side-on camera geometry

Front-on shadow boxing shows slips as lateral head movement and stance width
as left-right foot spread. Side-on, both become depth. Needs:

- a **view classifier** per track (which way the fighter faces, from
  shoulder/hip widths and nose position relative to the ears);
- a **sparring style profile** (`style_profiles.dart` pattern) that disables or
  re-tunes rules blind in profile — `head_movement` (lateral spread), parts of
  `footwork` and `body_lean` — and keeps the reliable ones (`guard_return`,
  `hands_up`, `hip_rotation` in-plane, punch detection, balance);
- re-calibration of the thresholds that stay, on own sparring footage (the
  CoachMe optimiser only has single-person, front-on data).

### C. Landed punches

In 2D a fist overlapping the partner's head is as likely 30 cm in front of it.
Pose can only say "a punch peaked near the partner's head/body"
(**candidate**); whether it landed is for the AI review, which sees the
reaction (head snap, step back). Report it as the AI's estimate, never as a
measured count.

### D. Defensive events

The library already excludes slips/rolls ("they need their own event model",
COMBINATIONS.md → Not yet). Sparring makes that model necessary: an event =
partner punch → user response within ~300 ms (guard raise, roll = head drops,
step back = hip-centre retreats, slip = head displacement, mostly depth in
profile). Pose can grade the in-plane ones; the AI grades the rest.

### E. Compute on the phone

Today a 2-minute round (3,601 frames at 33 ms) takes ~200 s on Grant's phone
(~55 ms/frame, CPU — the GPU delegate is disabled because it crashes
`createFromOptions` on some devices). MediaPipe runs the landmark model once
per detected person, so two fighters roughly **double** that: a 3-minute
sparring round ≈ 6–7 minutes of tracking; a 3 × 3 session ≈ 20 minutes.
Mitigations, in order of value:

1. sample sparring at **15 fps** (`sampleEvery` 66 ms) — halves it, and is
   enough for output, distance and timing; the AI review sees the video at
   24 fps anyway;
2. analyse each round **in the background as soon as it ends** (the rest
   minute is free compute; `BackgroundAnalysis` + keep-awake already exist);
3. revisit the GPU delegate on a device allow-list.

### F. Consent and privacy

The partner is filmed, their pose is measured and stored, and in the AI modes
the video (with them in it) is uploaded to Google. Needed before shipping:

- a **consent step** in sparring setup ("My sparring partner agreed to be
  filmed and analysed"), stored with the session;
- without consent: **AI modes off** for that session (the upload necessarily
  contains the partner), partner track **not stored or synced** (the user's
  track is enough for their own metrics);
- privacy policy + Play **Data safety** updates (data about people other than
  the user), and the account-deletion path covering partner data.

### G. AI context and cost

On current Gemini models video defaults to **low media resolution, ~66–70
tokens per frame**. A 3-minute round at 24 fps ≈ 4,300 frames ≈ **0.3 M
tokens**, well inside a 1 M context. Keep one request per round (a whole
3 × 3 session at 24 fps ≈ 0.9 M tokens is too close to the limit).
At Flash-Lite input prices (~$0.30 / M) that's roughly **$0.09 per round**; on
Flash ($0.75 / M until 31 Dec 2026, then $1.50) $0.23–0.45. Each round uses one
weekly AI analysis under the current quota.

## Proposed design

### Capture

- **Sparring** on the home screen: rounds (default 3), length (2–3 min), rest
  (1 min), partner consent, then the existing pre-flight
  (`RoundCaptureScreen` / session engine) per round with a rest timer between.
- **Landscape** for sparring capture only (unlock orientation on that screen),
  **1080p**, placement guidance: ring-side, ~waist height, far enough that
  both fighters stay head-to-feet in frame while they move.
- Each round is a clip (`RoundClip` with `SessionType.sparring`); its analysis
  starts in the background as soon as the round ends.

### Pose and tracking

- Plugin: `numPoses` parameter (1 | 2) passed from Dart; wire format gains
  `poses`; `lm` kept for compatibility.
- `analysis/tracking.dart` (new, pure Dart): `MultiPoseFrame` →
  `PoseTracker` (2-way assignment + ambiguity flags + signature re-ID) →
  `TrackedRound { Map<int, PoseSequence> tracks; Set<int> ambiguousFrames;
  Map<int, TrackSignature> signatures }`.
- Subject selection: `userTrackId` chosen by tap (round 1) or signature match
  (later rounds), stored on the session.

### Analysis

- **User:** the existing `PoseOnlyAdapter` on the user's track, with
  `SessionType.sparring` and the side-view profile. Everything downstream
  (corrections, moments, checkpoints if ever wanted) keeps working.
- **Interaction:** `analysis/sparring.dart` (new) over both tracks:
  distance timeline and range bands, output per fighter, exchanges, counters,
  guard under fire, punch-and-stay candidates, landed **candidates**. Result:
  `SparringAnalysis` persisted alongside the user's `RoundAnalysis`.
- **Partner:** punch counts and types only (for output and tendencies); no
  technique corrections for someone who isn't the user.

### AI review

- `CoachingPrompt.sparringVideoRequest`: identifies the user by description
  ("the fighter in black shorts, on the left at the start") **and** by a
  bounding-box track sampled at 2 Hz (normalised, from the tracker) so the
  model can't confuse them through crossovers; carries the user's measurements
  and the interaction metrics.
- Schema: the existing findings (same shape, so `AiReview` and moments reuse
  them, all about the user) + `exchanges` (start, end, who started, summary),
  `defence` (per partner attack sampled: response, verdict), `landed_estimate`
  per fighter, `partner_patterns` (what the partner did that worked).
- Moments: findings as today; exchanges become extra moments on the review
  screen.

### Data and sync

- `SessionType.sparring`; `RoundClip` carries `userTrackId` and consent flag.
- `AnalysisStore`: `pose.json` = user track (as now); `partner.pose.json` only
  with consent; `sparring.json` for `SparringAnalysis`.
- Supabase: a `sparring` JSONB column on `analyses` (or a `sparring_rounds`
  table) for the interaction metrics; partner pose uploaded only with consent;
  migration + RLS as existing tables.
- History: a sparring card per session — per-round output, range split,
  exchanges, counters, AI summary.

### UI

- Review screen: two skeletons (user accent, partner muted), toggle partner
  overlay; sparring summary panel; exchanges as moments.
- Progress card: unchanged stages (tracking now covers two people); show
  "Round 2 analysing" per round in the session view.

## What does not need to change

The engine's rules, combinations and checkpoints (they run per person), the
`RoundCoach` / `AiReview` seam, the proxy's video routes, `BackgroundAnalysis`,
keep-awake, the progress card, the sync queue's shape, the review screen's
moments plumbing.

## Phasing

Estimates are focused development days, rough, and assume the spike passes.

| Phase | Scope | Est. | Gate / output |
| --- | --- | --- | --- |
| **0 · Spike** | `numPoses = 2` behind a flag, dump multi-pose JSON; prototype tracker; run on 3–5 real sparring rounds (own gym footage, landscape, 1080p) | 2–3 | Both fighters detected in ≥ 90% of non-clinch frames; ≤ 1 unrecovered identity swap per round; tracking time ≤ 2.5× real time at 15 fps. **Go / no-go** |
| **1 · Capture + tracking** | plugin + wire format, `PoseTracker`, `TrackedRound`, sparring capture flow (landscape, rounds/rest, consent), "which one is you?", user analysis with the side-view profile, two-skeleton review, storage | 8–12 | Sparring rounds recorded and analysed for the user |
| **2 · AI sparring review** | sparring prompt + schema, user identification by description + box track, exchanges/defence/landed estimate in the review | 3–5 | Full AI review of a sparring round about the right fighter |
| **3 · Interaction metrics** | distance/range, output, exchanges, counters, guard under fire, sparring card in History, sync | 5–8 | Measured sparring stats per round and session |
| **4 · Defence events + evaluation** | defensive event model, landed candidates, labelled sparring set, threshold calibration, Python parity if wanted | 10+ | Calibrated, evaluated sparring analysis |

Phase 2 can ship before Phase 3: with tracking in place, the AI review alone
gives useful sparring feedback while the on-device interaction metrics follow.

## Decisions needed

1. **AI-led vs pose-led.** Recommended AI-led (pose for identity and the
   measurable stats). Pose-only sparring would be limited to output, distance,
   timing and the user's guard.
2. **Partner data.** Analyse and store the partner (needed for output share,
   exchanges, partner tendencies) only with consent — or never store the
   partner's pose, computing interaction metrics on the fly.
3. **Identity UX.** One tap after round 1 (recommended) vs "start on the left"
   before recording.
4. **Camera.** One phone, side-on, landscape (recommended) — a second phone is
   the multi-camera roadmap, not this.
5. **Quota.** Does a sparring round cost one weekly AI analysis like any other
   round (a 3 × 3 session = 3)?

## Risks

- **MediaPipe in clinches** — merged or swapped limbs; mitigated by ambiguity
  flags, not solved. Clinch-heavy sparring yields less measured data.
- **Small fighters in frame** — two full bodies in a landscape frame are
  roughly half the pixel height of one front-on fighter in portrait; landmark
  jitter rises. 1080p helps; the spike measures it.
- **Compute and battery** — two people at 15 fps is still minutes per round;
  the rest minute absorbs part of it.
- **Rule validity side-on** — some existing rules will mislead until re-tuned;
  the sparring profile must default to *off* for anything not re-validated.
- **Privacy** — partner consent and data-safety changes are a launch
  requirement, not polish.

## Sources

- Gemini video understanding — frame rate, default (low) media resolution and
  tokens per frame: <https://ai.google.dev/gemini-api/docs/video-understanding>
- Gemini media resolution token table:
  <https://ai.google.dev/gemini-api/docs/media-resolution>
- Gemini pricing: <https://ai.google.dev/gemini-api/docs/pricing>
