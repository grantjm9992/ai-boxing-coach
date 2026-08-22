# Changelog

All notable changes to the AI Boxing Coach app are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/); the project is
pre-1.0 and versioned by the v0.x delivery stages in
[`v0.5-pose-integration.md`](v0.5-pose-integration.md).

Feature areas referenced below have their own deep-dive docs — see
[`ARCHITECTURE.md`](ARCHITECTURE.md) for the index.

## [Unreleased]

### Added
- **History list loads from the database.** The History tab now rebuilds its
  list from Supabase (`SupabaseHistoryReader.listSessions()`) and merges it with
  the on-device history — cloud authoritative per session, local filling
  unsynced/offline gaps — so past sessions survive a reinstall or appear on
  another device. The weekly category balance is rolled up from the merged set.
  Falls back to local-only when signed out or offline. (PR #15)
- **Session rollup persisted to the cloud.** Total/work seconds, round count and
  category seconds are written into `sessions.plan` at finalize time (plumbed
  through the durable sync queue) so the list above has the totals the per-round
  rows don't carry. See [`BACKEND_SYNC.md`](BACKEND_SYNC.md).

### Changed
- **Pose frames convert straight to a Bitmap.** The native Android pose plugin
  dropped its per-frame `YUV → NV21 → JPEG-encode → JPEG-decode → Bitmap` round
  trip for a single integer BT.601 pass straight to `ARGB_8888`. Resolution and
  frame rate are unchanged; the dominant per-round cost is removed. See
  [`POSE_ANALYSIS.md`](POSE_ANALYSIS.md). (PR #16)

## Earlier stages

These landed before the changelog was started; grouped by feature area rather
than dated.

### Analysis & coaching
- Moment-by-moment analysis: a 7-frame burst is captured around each flagged
  correction, everywhere it's shown (review, history, AI keyframe payload).
- Analysis modes behind a provider adapter: **offline** (pose + rules),
  **pose + AI on key moments** (keyframe), and **full AI review** (parked behind
  a "Coming soon" badge until the self-hosted endpoint lands).
- Release-build pose analysis fixed (R8 keep rules) and AI review modes wired up.
- Larger AI token budget; a countdown before the first round; an "analysing"
  badge on the live screen.
- Review screen reads the session's saved analysis instead of recomputing it.
- Calibration loop: export a round's pose data and run it through the Python
  reference engine; guard-return no longer false-flags a buzzer-beater punch.

### Backend & sync
- Supabase schema + auth (email + Google OAuth), phases 1–2.
- Round sync: session/round/analysis rows plus pose sequence and keyframe images
  to Storage; idempotent upserts.
- History detail reads full feedback + keyframes back from Supabase, so it
  outlives the local 7-day clip sweep.
- Durable backfill queue: rounds recorded offline (or whose sync failed) retry
  on a later launch or sign-in.
- On-device debug log + in-app sync-outcome reporting for release-APK debugging.

### Recording & session
- Camera records **technical work rounds only**, video-only (no audio).
- 7-day clip retention sweep, enforced on every launch.
- User profile: stance / style / national school, coached against every round.
- Perf: stream-decode the clip instead of re-seeking every frame.
