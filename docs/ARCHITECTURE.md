# Architecture overview

The AI Boxing Coach is a Flutter app (`app/`) that runs interval boxing
sessions, records technical rounds on the front camera, analyses each round
on-device with pose estimation + a rule engine, optionally enriches the feedback
with a vision-language model, and syncs the results to Supabase so history
survives a reinstall.

A Python reference engine lives under `src/` — it is the source of truth the
Dart rule engine mirrors, used for calibration, not shipped in the app.

## Documentation index

| Doc | Covers |
| --- | --- |
| [`SESSION_ENGINE.md`](SESSION_ENGINE.md) | Templates → plan → the timed session, coach cues, voice |
| [`RECORDING_STORAGE.md`](RECORDING_STORAGE.md) | Camera recording, clip store, 7-day retention, local persistence |
| [`POSE_ANALYSIS.md`](POSE_ANALYSIS.md) | Native pose plugin, the Dart rule engine, punch classification, metrics |
| [`COMBINATIONS.md`](COMBINATIONS.md) | Combination detection, execution scoring, drills + library (V2) |
| [`AI_INTEGRATION.md`](AI_INTEGRATION.md) | Analysis modes, the vision-model seam, coaching prompts, the structured advanced path |
| [`ANALYTICS.md`](ANALYTICS.md) | V2 analytics event taxonomy + the regression-dataset scaffold |
| [`V2_PLAN.md`](V2_PLAN.md) | The V2 hybrid-analysis build, phase by phase |
| [`BACKEND_SYNC.md`](BACKEND_SYNC.md) | Supabase schema, auth, round sync, backfill queue, history read-back |
| [`backend-setup.md`](backend-setup.md) | One-time Supabase project setup (operator guide) |
| [`v0.5-pose-integration.md`](v0.5-pose-integration.md) | The original design/decision record for pose integration |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed, by release stage |

## The end-to-end flow

```
Template + profile
   │  SessionPlanBuilder
   ▼
SessionPlan (flat segment list)
   │  SessionEngine (clock) ──► CueScheduler ──► CoachVoice (TTS)
   ▼
Technical work round starts
   │  RoundRecordingController ──► CameraRoundRecorder ──► RoundClip (mp4)
   ▼
Round ends ──► RoundAnalyzer
   │  1. MediaPipe pose  ──► PoseSequence
   │  2. RuleEngine + PoseOnlyAdapter ──► RoundAnalysis (offline)
   │  3. (AI modes) VisionModel over flagged/​sampled frames ──► coaching
   ▼
AnalysisStore (local JSON, beside the clip)
   │
   ├─► SessionHistoryStore (thin per-session rollup, survives the clip sweep)
   └─► BackfillQueue ──► SupabaseRoundSync ──► Supabase (rows + Storage blobs)
                                                   ▲
History screen ◄── SupabaseHistoryReader ◄─────────┘  (merged with local)
```

## Layering

- **`domain/`** — plain data: `SessionTemplate`, `SessionPlan`,
  `SessionRecord`, `UserProfile`, `RoundClip`, `SkillCategory`. No I/O.
- **`data/`** — static catalogs: the exercise library and session templates.
- **`engine/`** — the pure session state machine and coach script
  (`SessionEngine`, `CueScheduler`, `SessionPlanBuilder`). Testable without a
  device.
- **`analysis/`** — pose types, the rule engine, punch + combination detection,
  combination-execution scoring, the structured AI report schema and the
  regression-dataset scoring. Pure; no plugins or platform channels. (The rule
  engine is a Dart mirror of the Python reference; the V2 additions are
  Dart-first.)
- **`services/`** — everything with a side effect: camera, pose plugin, stores,
  AI calls, auth, sync. Each wraps a plugin behind a small interface so the
  engine and UI depend on seams, not SDKs.
- **`ui/`** — screens and widgets.

## Cross-cutting principles

- **On-device first.** Pose + rules always run locally; they're free, offline
  and private, and give the metrics, the review skeleton and base coaching with
  no network. AI is *additive* — no model, key or network still leaves a
  complete offline analysis. See [`AI_INTEGRATION.md`](AI_INTEGRATION.md).
- **Best-effort sync, never a broken session.** Recording, analysis and sync are
  wrapped so a failure is logged and retried, never thrown into the session
  loop. The [`BackfillQueue`](BACKEND_SYNC.md) makes "upload when online"
  durable.
- **Local is the source of truth for a live session; the cloud is the source of
  truth for history.** The 7-day clip sweep reclaims video, but analysis is
  rolled up locally and mirrored to Supabase, so history outlives the clip.
- **Pure where it can be.** The engine, rules, plan builder, prompt building and
  retention sweep are pure functions with injectable clocks/dirs, so they're
  unit-tested with no camera, no plugin and no server (`app/test/`).
