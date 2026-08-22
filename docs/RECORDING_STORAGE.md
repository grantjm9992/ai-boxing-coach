# Recording & local storage

How a technical round gets captured on the camera, where the clip and its
analysis live on-device, and the retention policy that stops them living there
forever.

Code: `app/lib/services/camera_round_recorder.dart`,
`round_recording_controller.dart`, `round_recorder.dart`, `clip_store.dart`,
`analysis_store.dart`, `session_history_store.dart`, `frame_grabber.dart`.

## What gets recorded

`shouldRecordSegment()` (`round_recording_controller.dart`) is a pure function:
record **technical work rounds only** — the phase whose whole point is one
technique done properly, and the one the v1 detections (guard return, punch
retraction) are about. Rest periods, warm-ups and conditioning are left alone.

`RoundRecordingController` turns the session's segment transitions into camera
start/stop calls and produces a `RoundClip` per recorded round.

## The camera

`CameraRoundRecorder` (`camera_round_recorder.dart`) is the real
`RoundRecorder` — a thin wrapper over a `CameraController`:

- **Video only** — `enableAudio: false`. Pose analysis has no use for sound, and
  dropping it also drops the microphone permission.
- **Front camera** preferred, so the camera-check preview mirrors the athlete
  while they get in frame.

`RoundRecorder` is an interface, so the controller and session can be tested with
a fake recorder — no camera.

## On-device storage

Three stores, all with injectable `baseDir` / `now` so their behaviour is
unit-tested against a temp directory and a fake clock.

| Store | Holds | Lifetime |
| --- | --- | --- |
| `ClipStore` | The recorded `.mp4` clips + `RoundClip` metadata. | **7 days**, then swept. |
| `AnalysisStore` | Each round's `RoundAnalysis` + `PoseSequence`, as JSON beside the clip. | Swept with the clip. |
| `SessionHistoryStore` | A thin per-session rollup (one JSON file per session). | Kept — outlives the clip. |

### The 7-day retention sweep

`ClipStore` implements the spec's answer to its own open question: *keep clips 7
days, then delete unless explicitly saved; analysis persists.* The design note is
blunt — "a retention policy added later is a retention policy that never ships" —
so the sweep is written alongside the writing and is the part that gets a unit
test. `ClipStore().sweepExpired()` runs on every launch (fire-and-forget in
`main.dart`).

Because the video is reclaimed after 7 days but analysis must outlive it, the
analysis is rolled up two ways:

1. **Locally** into `SessionHistoryStore` at session end (survives the clip
   sweep, powers the History list + weekly balance offline);
2. **To the cloud** via round sync (survives a reinstall / another device) —
   see [`BACKEND_SYNC.md`](BACKEND_SYNC.md).

### AnalysisStore

Keyed by session + segment. The analysis JSON is small; the pose sequence is a
few hundred KB and lets the review screen redraw the skeleton without re-running
MediaPipe. Round sync reads what to upload from here, so the on-device copy stays
the source of truth.

### FrameGrabber

`frame_grabber.dart` pulls specific timestamps out of a clip as image bytes —
used to grab the keyframe bursts for the review/history views and the AI
keyframe payload ([`AI_INTEGRATION.md`](AI_INTEGRATION.md)).

## Persistence shapes

- `RoundClip` (`domain/round_clip.dart`) — a recorded round: session id, segment
  index, phase, path, recorded-at, round metadata.
- `SessionRecord` / `RoundSummary` (`domain/session_record.dart`) — the history
  rollup. `SessionRecord.rollupJson` is the session-level summary
  (total/work seconds, round count, category seconds) that also gets persisted to
  the cloud so the History list can be rebuilt on another device.
