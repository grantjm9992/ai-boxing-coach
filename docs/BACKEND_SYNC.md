# Backend & sync

How the app persists to Supabase and reads history back. This is the
*architecture* — for one-time project setup (running the migration, enabling
auth providers, config), see [`backend-setup.md`](backend-setup.md).

Code: `app/lib/services/auth/`, `app/lib/services/supabase/`,
`app/lib/services/sync/`, `supabase/migrations/`.

## Schema

`supabase/migrations/0001_init.sql` (plus `0002_keyframe_grouping.sql`). The
shape mirrors the on-device model: a user runs **sessions**; a session has
**rounds**; a round has one **analysis** and a handful of **keyframes**. Large
blobs live in Storage; rows hold their paths + the metadata actually queried.

| Table | Key columns |
| --- | --- |
| `profiles` | 1:1 with `auth.users`; mirrors `UserProfile` (stance, style, school, analysis_mode). |
| `sessions` | `client_session_id` (the app's timestamp id, unique per user), `title`, `plan` (jsonb), `started_at`, `ended_at`. |
| `rounds` | `session_id`, `segment_index`, `round_number`, `title`, `duration_ms`, `pose_path`. Unique `(session_id, segment_index)`. |
| `analyses` | `round_id` (unique), `mode`, `summary`, `metrics`, `corrections`, `positive_notes`, `ai_coaching`. |
| `keyframes` | `round_id`, `storage_path`, `timestamp_ms`, `correction_ref`, `correction_index`, `mime`. |

Every table carries a denormalised `user_id` so **Row-Level Security** is a
trivial `user_id = auth.uid()` on each — no joins in policies. Storage buckets
(`keyframes`, `pose`, `clips`, all private) key their RLS off the first path
segment being the user id:

```
keyframes/<uid>/<session>/<segment>/<moment>_<ts>.jpg
pose/<uid>/<session>/<segment>.pose.json
clips/<uid>/<session>/<segment>.mp4        (retained locally for now)
```

> **`sessions.plan`** carries the session-level rollup (total/work seconds,
> round count, category seconds) written at finalize — this is what lets the
> History list and weekly balance be rebuilt from the cloud. See *History
> read-back* below.

## Auth

`AuthService` (`services/auth/auth_service.dart`) wraps the Supabase SDK behind a
small, testable surface. `AuthService.initialize()` runs once before `runApp`.
Email and Google OAuth are supported; the OAuth redirect
(`com.aiboxingcoach.boxing_coach://login-callback`) matches the Android manifest
intent-filter. A DB trigger auto-creates a `profiles` row on sign-up.

The UI gates on auth via `ui/screens/auth_gate.dart`.

## Round sync (write path)

`SupabaseRoundSync` (`services/sync/round_sync.dart`) pushes a finished round up.
It reads *what* to upload from the local `AnalysisStore` — the on-device copy
stays the source of truth and this is pure "upload when online". Everything is
best-effort and **idempotent via upserts**, so a re-analyse or a backfill is
safe.

`syncRound()` does, in order:

1. **Session row** — upsert on `(user_id, client_session_id)`.
2. **Round row** — upsert on `(session_id, segment_index)`.
3. **Pose sequence** → Storage (`pose` bucket).
4. **Analysis row** — upsert on `round_id`.
5. **Keyframe images** — a burst per flagged moment (the same frames the model
   reviews), grabbed from the clip, uploaded to the `keyframes` bucket with rows
   grouped by `correction_index` + `correction_ref`. Existing frames for the
   round are deleted first so a re-sync doesn't duplicate.

`finalizeSession()` marks the session finished (`ended_at`) and writes the
**rollup** into `sessions.plan`. Safe to call even if no round synced.

Outcomes are reported as a `SyncOutcome` (`uploaded` / `skippedSignedOut` /
`skippedNoAnalysis` / `failed`) — never thrown, so sync can't break a session.
During bring-up these surface in-app (and in the on-device debug log) so a
release APK on a device tells you exactly what happened.

## The backfill queue (durability)

`BackfillQueue` (`services/sync/backfill_queue.dart`) is a durable "upload when
online" queue on top of round sync. A round recorded offline — or a sync that
failed — is enqueued (persisted to disk) and retried later, so nothing recorded
is lost.

- **`SyncJob`** — one unit of work: sync a round, or finalize a session (which
  carries the `title` and the `rollup`). One job per round / per session;
  re-enqueuing replaces rather than dupes.
- **`process()`** drains the queue: runs each job, drops the ones that land or
  are terminally un-syncable (analysis swept), keeps failures for a later
  attempt, and stops early when signed out / offline.
- Jobs past the 14-day max age are dropped (their keyframes are gone with the
  7-day clip sweep, so they can never complete).

The queue is drained on app start, on sign-in, and after each round / session
(see `main.dart`).

## History read-back (read path)

`SupabaseHistoryReader` (`services/sync/history_reader.dart`) is what lets old
feedback — and the frames it points at — survive the local 7-day sweep and show
up on a fresh install / another device. Best-effort: signed out, offline, or any
failure returns null/empty and the caller falls back to local.

- **`listSessions()`** rebuilds the whole History list: one `SessionRecord` per
  session, newest first, with the rollup from `sessions.plan` and a thin
  per-round summary (a round counts as analysed when it has an analysis
  summary). The History screen **merges** this with the local list — cloud
  authoritative per session id, local filling unsynced/offline gaps — and rolls
  the weekly balance up from the merged set.
- **`loadSession()`** loads one session's full detail for the history-detail
  view: the full per-round analysis and short-lived **signed URLs** for keyframe
  images, grouped moment by moment (by `correction_index`).

### Caveats

- The rollup is written only for **recorded** sessions (finalize gates on
  recording being enabled). Non-recorded sessions live only in local history.
- Sessions synced **before** the rollup was introduced have no
  `sessions.plan`, so their reconstructed tile shows 0 minutes and falls back to
  counting round rows, until re-synced.
