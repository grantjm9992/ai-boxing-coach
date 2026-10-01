# Sparring mode

Status: **built, first version.** Implements the design in
`docs/SPARRING_PLAN.md` (PR #54), with these decisions:

- The AI review uses the **same weekly allowance** (one analysis per round).
- **Full corrections and stats for both fighters.**
- **No consent step.** Sparring happens in the gym, where consent is given.

The thresholds are starting points. Calibrating them on real sparring footage is
the next job (see [Calibration](#calibration)).

## What the user gets

1. **Home → Sparring → Set up sparring.** Choose the number of rounds, round
   length, rest, the partner's name, what each of you is wearing, and whether the
   AI coach reviews each round. The whole of sparring mode runs in **landscape**.
2. **Capture.** Back camera at 1080p, propped ringside. The screen shows a
   countdown, a round timer with bells and a rest timer, and starts each next
   round on its own. Each finished round starts analysing straight away, during
   the rest.
3. **Session screen.** Lists the rounds with their progress, and totals for both
   fighters. After the first analysed round it asks **"Which one is you?"**: you
   tap yourself once, and every round after that is labelled You and Partner.
4. **Round review.** The video shows both skeletons, colour-coded (you in red,
   your partner in blue), and you can toggle each. There are three tabs:
   - **One tab per fighter:** the AI's read, punches, per-minute output, stance,
     punch mix, corrections that jump to their moment in the video, strengths,
     the AI's tendencies, and the AI's estimate of punches landed.
   - **Together:** time at each range, a head-to-head table (exchanges started,
     counters, hands up while being punched at, step-backs and ducks, fists that
     reached the head or body in 2D), exchanges, the AI's defence samples, and
     any time that wasn't analysed.
5. **Check who's who.** Shown whenever the tracker wasn't sure which fighter was
   which. You see the moment with the body in question outlined, and answer
   "yes", "it's …" or "neither". The round is re-tracked and re-measured from the
   stored poses in about a second, with no re-extraction.
6. **History → Sparring tab.** Lists past sessions. The existing Sessions tab is
   unchanged.

## Pipeline (separate from the single-person one)

```
SparringCaptureScreen ─► SparringStore (clip)
        │
        ▼
SparringJobs (own queue, keep-awake, progress)
  1. SparringPoseService ─► sparring_pose plugin (every body + appearance, 20 fps, full model)
  2. FighterTracker: TrackletBuilder ─► IdentityLinker ─► TrackedRound (A/B sequences, gaps)
  3. SparringAnalyzer: FighterAnalyzer ×2 (existing RuleEngine, read-only) + InteractionAnalyzer
  4. SparringCoach ─► `sparring` edge function ─► Gemini (optional)
  5. SparringStore (frames, tracking, decisions, analysis) ─► SparringSyncQueue ─► Supabase
```

| Piece | Where |
| --- | --- |
| Native multi-pose extraction | `app/packages/sparring_pose/` (Kotlin + Swift + Dart) |
| Pose types | `lib/sparring/pose/` (`PoseCandidate`, `MultiPoseFrame`, `MultiPoseRound`, `SparringPoseService`) |
| Tracking | `lib/sparring/tracking/` (`TrackletBuilder`, `IdentityLinker`, `FighterTracker`, appearance) |
| Analysis | `lib/sparring/analysis/` (`sparring_profile`, `FighterAnalyzer`, `InteractionAnalyzer`, `SparringAnalyzer`) |
| AI | `lib/sparring/ai/` (`SparringPrompt`, `SparringAiReport`, `SparringReview`, `SparringCoach`) |
| Storage + sync | `lib/sparring/data/` (`SparringStore`, `SparringSyncQueue`) |
| Background work | `lib/sparring/jobs/sparring_jobs.dart` |
| Screens | `lib/sparring/ui/` |
| Edge function | `supabase/functions/sparring/` (imports `../analyze/video.ts` read-only) |
| Schema | `supabase/migrations/0005_sparring.sql` |

**Isolation.** Outside those folders, sparring touches only these entry points:
- `home_screen.dart`: the Sparring accordion.
- `history_screen.dart`: the Sessions / Sparring tabs; the Sessions content is
  unchanged.
- `pubspec.yaml`: the new package.

From the existing code, sparring *calls* the following read-only, with its own
settings: `PoseSequence`, the rules, `RuleEngine`, `AnalysisContext`,
`resolveProfile`, `AiPriorityIssue.tryFrom`, `CoachVideoModel` (pointed at the
sparring function), `KeepAwake` and `AppForeground`.

`scripts/check_sparring_isolation.sh` fails a sparring change that edits
anything else. CI runs it in `.github/workflows/sparring-check.yml`, alongside
the analyzer, the whole test suite and the edge-function tests.

## Tracking both fighters

This is the core of the feature. It runs offline over the whole recorded round.

1. **Extraction** (`sparring_pose`). MediaPipe runs in VIDEO mode with up to
   **3** bodies per frame, not 2. A coach or another pair in shot could otherwise
   take a fighter's slot, because VIDEO-mode tracking keeps whatever it locked
   onto. Each body comes back with:
   - its 33 landmarks;
   - an **appearance descriptor**: two 11-bin HSV colour histograms, one for the
     torso and one for the shorts. They are sampled in the same decode pass from
     regions the pose locates. Bins 0–7 are hue, 8 black, 9 grey, 10 white.

   Frames stream back to Dart in batches of 20.
2. **Tracklets** (`TrackletBuilder`). Bodies are linked frame to frame only while
   the match is unambiguous. Each link is checked against:
   - the predicted hip position (damped constant velocity), gated in
     torso-lengths;
   - appearance distance;
   - a scale change;
   - a hard reject for implausible limb proportions (merged skeletons).

   A tracklet **ends** instead of guessing when bodies overlap (IoU > 0.3), when
   the best assignment beats the runner-up by less than 0.25, or after a gap of
   more than 6 frames.
3. **Identities** (`IdentityLinker`). Every tracklet is labelled A, B or neither
   over the **whole round** at once.
   - Costs come from appearance, body shape (limb/torso ratios) and size compared
     with each fighter's template, plus continuity between one fighter's
     consecutive tracklets.
   - Co-occurring tracklets can't share a label.
   - With two labels the state is just each fighter's latest tracklet, so a
     dynamic programme finds the best labelling exactly (capped at 256 states).
   - Each tracklet gets a **margin**: how much worse the best labelling gets when
     that tracklet is labelled differently.
   - Without a reference, templates are seeded from the pair seen together
     longest (the bigger pair, so bystanders lose), refined over 3 passes, and A
     is whoever starts on the left.
4. **Never guess.**
   - A labelled tracklet with a margin under **0.15** is **excluded** until the
     user decides.
   - Under **0.6**, it's used but goes to "Check who's who".
   - Frames where a fighter isn't resolved are empty in their sequence.
   - Any punch touching an unresolved frame is dropped, and so is any observation
     within 5 frames of one.
5. **Who's who across rounds.** "Which one is you" saves the user's and partner's
   templates on the session. Every round is then re-linked against them, so
   **A = the user**. A round that doesn't clearly match (small `swapMargin`) can
   be checked.
6. **Corrections.**
   - Decisions are stored per round as tracklet id → label.
   - A swap moves the partner too: whoever held the target label alongside that
     tracklet takes its old label.
   - After any re-track, the AI review is kept if the labels didn't move, swapped
     if A and B flipped wholesale, and otherwise marked stale with a "Re-run"
     button (`compareLabels`).

Tests (`test/sparring/tracking_test.dart`) cover the following on synthetic
side-on footage: fighters apart, a crossing, a clinch re-linked by kit, the same
kit with different builds, a bystander, a session reference with sides swapped,
forced labels and JSON round-trips. Each checks that **no frame is attributed to
the wrong person**.

## Analysis

- **Per fighter** (`FighterAnalyzer`). That fighter's `PoseSequence` goes through
  the unmodified `RuleEngine` with the **side-view-valid rules only**:
  `guard_return`, `hands_up`, `hip_rotation` and `balance`.
  - The sparring `StyleProfile` switches off `head_movement`, `footwork`,
    `body_lean` and `school_adherence`, which use front-on geometry, and excuses
    hands-up while moving.
  - The user's stance, style and school come from their profile. The partner's
    stance is **inferred** (the lead foot is the one nearer the opponent).
- **Together** (`InteractionAnalyzer`):

  | Metric | How it's measured |
  | --- | --- |
  | Distance | Hip-to-hip in torso-lengths: inside < 2.2 ≤ mid < 3.4 ≤ long |
  | Exchanges | Punches less than 1 s apart, with at least 2 punches |
  | Counters | A punch within 0.6 s after the other's |
  | Guard under fire | Both wrists above the shoulder line for at least 70% of the other's punch |
  | Defence (in-plane) | Duck: head drops by 0.25 torso. Step back: hips retreat by 0.3 torso |
  | Landed candidates | The fist reaches the head (0.45 torso from the nose) or the torso box in 2D. Shown as "reached", never as landed |

## AI review

`SparringPrompt` sends the whole round at 24 fps along with:
- each fighter's description (name, stance, style or school, typed kit, the kit
  colours the camera saw, the starting side);
- a **box track per fighter every 0.5 s**;
- the windows the tracker couldn't resolve;
- both fighters' measurements and the interaction metrics, as JSON.

The schema asks for:
- a top-level summary;
- for each fighter (`fighter_a`, `fighter_b`): a summary, strengths, up to 7
  `priority_issues` in the same shape as the single-person review, a
  `landed_estimate` and patterns;
- `exchanges` and `defence` samples.

`SparringReview` keeps each fighter's findings with confidence ≥ 0.6 and a
timestamp inside the round. Duplicates (same code within 1.5 s) are merged. The
rest are sorted worst first, capped at 7, and shown as that fighter's
corrections. Measurements stay on-device.

**Edge function `sparring`.** It has the same routes as `analyze`'s video ones
(`/video/upload`, `/video/generate`) and the same quota RPCs, so it draws on the
same allowance and refunds on failure. Differences from `analyze`:
- output budget up to **16,384 tokens**;
- size cap of 800 MB;
- optional `AI_SPARRING_MODEL`.

Deploy it with `supabase functions deploy sparring`. Secrets are shared with
`analyze`.

**Cost.** At low media resolution a 3-minute round at 24 fps is about 0.3 M
input tokens, the same as one single-person Full AI review of that length.

## Data

- **On device:** `<documents>/sparring/<session>/`. It holds `session.json`, and
  per round:
  - `clip.mp4` (deleted after 7 days);
  - `frames.json.gz` (every body, every frame, so tracking can be redone);
  - `decisions.json`, `tracked.json`;
  - `fighter_a.json` and `fighter_b.json` (`PoseSequence` JSON);
  - `analysis.json`.
- **Supabase:**
  - Tables: `sparring_sessions`, `sparring_rounds` (interaction, AI report) and
    `sparring_fighters` (one row per fighter per round: metrics, findings,
    summary, pose path). All have owner-only RLS.
  - Storage: the `sparring` bucket.
  - Uploads go through `SparringSyncQueue`, which is durable and retried when
    sparring screens open.

## Calibration

These are starting points; measure them on real footage before trusting the
numbers:

- **Tracker.** Gate 0.6 + 0.35 per frame, overlap IoU 0.3, link margin 0.25,
  exclude below 0.15, review below 0.6. Targets (from the plan): 0 identity
  switches after confirmation, IDF1 ≥ 98% on non-ambiguous frames, ≤ 5%
  ambiguous outside clinches.
- **Distance bands** 2.2 / 3.4 torso-lengths, counter window 0.6 s, exchange gap
  1 s.
- **Compute.** Expect roughly 5–8 minutes per 3-minute round on a mid-range
  Android phone (CPU, full model, up to 3 bodies). The rest minute absorbs part
  of it.
- **iOS.** The Swift plugin maps sample points through the clip's orientation;
  check the appearance histograms on a rotated clip. `.github/workflows/ios-build.yml`
  (manual) compiles the iOS app.

## Not yet

- A defensive event model beyond in-plane duck and step-back (slips are depth
  side-on). The AI grades these for now.
- Cloud listing of sparring sessions in History. It reads the device store only.
- Ring position (no ring model).
- An evaluation set of labelled real rounds (`evaluation/sparring/`) and
  recorded multi-pose fixtures from real footage.
