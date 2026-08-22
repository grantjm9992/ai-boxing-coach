# Session engine

How a workout goes from a template the user picked to a running, spoken,
timed session. Everything here is pure Dart with an injectable clock, so the
whole engine runs in a plain test with a `SilentCoachVoice`.

Code: `app/lib/engine/`, `app/lib/domain/session_*.dart`,
`app/lib/data/session_templates.dart`, `app/lib/services/coach_voice.dart`.

## The pieces

| Type | File | Role |
| --- | --- | --- |
| `SessionTemplate` | `domain/session_template.dart` | A named workout: phases and their items. |
| `SessionSettings` | `domain/session_settings.dart` | The user's per-run overrides (round count, durations…). |
| `SessionPlanBuilder` | `engine/session_plan_builder.dart` | Expands template + settings into a flat segment list. |
| `SessionPlan` / `SessionSegment` | `domain/session_plan.dart` | The flat list the timer walks. |
| `CueScheduler` | `engine/cue_scheduler.dart` | Precomputes the coach's whole script from the plan. |
| `CoachCue` | `engine/coach_cue.dart` | One scheduled utterance/sound at an offset. |
| `SessionEngine` | `engine/session_engine.dart` | Keeps the clock, walks segments, fires cues. |
| `CoachVoice` | `services/coach_voice.dart` | The TTS/audio seam (`DeviceCoachVoice` in the app). |

## From template to segments

`SessionPlanBuilder` collapses two different structures into one flat list:

- **Continuous phases** (warm-up, cool-down) divide the phase's total time
  across their items *in proportion to each item's natural length* — stretching
  a warm-up from 5 to 10 minutes stretches every step, rather than bolting extra
  time onto the end.
- **Round-based phases** repeat work/rest pairs, cycling through the template's
  items if the user asks for more rounds than the template names.

Segments shorter than `minimumSegmentSeconds` (20s) aren't worth announcing and
are dropped. Each `SessionSegment` carries its phase, kind (`work`/`rest`),
index, round number and title in metadata — the phase *structure* lives in the
segments, not in a nested tree, which keeps the timer and scheduler simple.

Each segment maps to skill categories (`SkillCategory`), which is what the
weekly balance view and the session rollup aggregate.

## The coach script

`CueScheduler` computes the **entire** script up front rather than deciding tick
by tick. That makes the coach deterministic — the same plan always yields the
same cues — which is testable, and it means the engine at runtime only compares
time offsets.

The rules it encodes (from the spec's "Coach behaviour" section):

- anticipate the next round, and call the round in;
- mark halfway and the last ten seconds;
- drop a technique reminder every 20–30s, the first landing at 20s in (not at
  the top of the round — the athlete was just told what to do);
- acknowledge milestones.

## Running it

`SessionEngine` is a `ChangeNotifier`. Time is advanced through `advance()`
rather than read from the wall clock inside the state machine:

- the real session drives `advance()` from a periodic timer that measures
  elapsed time with a `Stopwatch`, so a slow frame delays a cue but never loses
  one, and drift doesn't accumulate;
- tests drive `advance()` directly and deterministically.

State moves through `SessionStatus.ready → running → paused → completed`. As the
engine crosses a cue's offset it calls `CoachVoice.speak(text, priority)` /
`playSound()`.

`CoachVoice` is the seam that keeps the engine free of TTS plugins. Its contract:
a `CuePriority.critical` cue is never dropped; a `CuePriority.routine` cue never
interrupts one already being spoken. The app uses `DeviceCoachVoice`
(flutter_tts); tests use `SilentCoachVoice`.

## Where recording and analysis hook in

The session screen watches segment transitions and, for **technical work rounds
only**, drives the camera through `RoundRecordingController` — see
[`RECORDING_STORAGE.md`](RECORDING_STORAGE.md). When a round ends its clip is
handed to `RoundAnalyzer` ([`POSE_ANALYSIS.md`](POSE_ANALYSIS.md) /
[`AI_INTEGRATION.md`](AI_INTEGRATION.md)), and in a rest period the engine may
speak the resulting coaching.
