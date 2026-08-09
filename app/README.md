# AI Boxing Coach — v0.1 (Flutter)

The v0.1 proof of concept from [`boxing-coach-spec.md`](../boxing-coach-spec.md):

> **v0.1 (proof of concept):** Timer + basic coach cues + exercise library +
> session templates. No AI. Confirm the coaching UX works.

One Dart codebase, native iOS and Android builds. **No AI, no camera, no
recording, no pose analysis** — those arrive at v0.5 and are deliberately absent
here. The one question this build exists to answer is whether being coached
through a structured session by a phone actually feels like being coached.

The Python pose-analysis engine in [`../src/boxing_coach/`](../src/boxing_coach)
is untouched by this app and stays the v0.5 foundation.

---

## What it does

**Structured sessions.** Five pre-built templates, each running the full arc —
warm-up → conditioning → shadow → technical → cool-down — with the intent of
each phase stated up front. The warm-up and cool-down cannot be switched off;
the round-based phases can.

**Configurable within bounds.** Round count, round length, rest, and the length
of the continuous phases are all adjustable, but only inside the ranges the spec
gives each phase. Stretching the warm-up from five minutes to ten stretches
every step of it rather than bolting the extra time onto the end. The
configuration is remembered per template.

**An anticipatory coach, not a timer with a bell.** The whole cue script is
computed when the session is built, so what the coach will say is deterministic
and testable. It:

- announces each round with its theme and calls the last round of a phase;
- previews the next round thirty seconds before it starts, with a hint from the
  drill that is coming ("Get ready. Next round is defence focus. Defend and
  move — do not just cover and stand there.");
- calls halfway, thirty seconds, and the last ten;
- drops technique reminders every twenty-five seconds, drawn from the exercise
  being worked, and **drops** rather than queues any that would land on top of a
  round call — the coach does not talk over itself;
- marks the halfway point of the session and recaps at the end.

Voice is device TTS (English only, per the MVP scope); the bells and countdown
ticks are bundled WAV assets. Either can be muted independently — bells with
your own music on is a normal way to train.

**Exercise library.** ~50 exercises across the five phases, each tagged with
weighted skill categories (cardio, power, footwork, defence, combinations, head
movement, distance management, and the rest of the spec's list), each carrying
its own coach cues. Filterable by phase and category.

**Category balance.** Weighted working minutes per category, shown before the
session and again at the end. This is the same weighted-minutes model the weekly
dashboard will use once v0.5 starts keeping history.

## What it does not do

Everything the spec puts after v0.1: recording, pose estimation, technique
analysis, API enrichment, style-aware coaching, session history, weekly
dashboards, multi-language coaching, wearables. v0.1 keeps **no data** beyond
your slider positions.

---

## Layout

```
lib/
  domain/       plain data: phases, exercises, templates, settings, plans
  data/         the exercise library and the session templates
  engine/       plan builder, cue scheduler, session engine (no Flutter UI)
  services/     coach voice (TTS + audio), settings storage
  ui/           screens, widgets, theme
test/           engine, scheduler, library and widget tests
assets/audio/   bell / tick / warning / finish cue sounds
tool/           regenerates the cue sounds
```

Three seams matter:

- **`SessionPlanBuilder`** turns a template plus settings into a flat list of
  `SessionSegment`s. Phase structure lives in segment metadata, so the timer
  never has to understand the difference between a warm-up step and a round.
- **`CueScheduler`** turns that plan into the coach's script up front. Same plan,
  same script, every time.
- **`SessionEngine`** advances only through `advance(Duration)`. In the app a
  periodic timer feeds it deltas measured by a `Stopwatch`, so a slow frame
  delays a cue but never loses one and drift does not accumulate. In tests the
  same method is called directly, which is why the engine is testable without a
  clock, a screen or a speaker.

`CoachVoice` is an interface; `SilentCoachVoice` is what the tests run against.

---

## Build and run

### Prerequisites

- Flutter 3.44 or newer (`environment: sdk: ^3.12.2`)
- Android: Android SDK 36 + JDK 17 or newer
- iOS: macOS with Xcode 15+, CocoaPods

```bash
cd app
flutter pub get
flutter analyze     # clean
flutter test        # 55 tests
dart format lib test
```

### Run on a connected device

```bash
flutter devices
flutter run -d <device-id>
```

The coach speaks through the device TTS engine, so use a real device — a
simulator's TTS behaviour is not representative.

### Android — install on a real phone

1. On the phone: Settings → About phone → tap *Build number* seven times, then
   Settings → Developer options → **USB debugging** on.
2. Plug it in and accept the debugging prompt.
3. ```bash
   flutter devices                 # confirm the phone is listed
   flutter run --release           # builds, installs and launches
   ```

To hand someone an APK instead:

```bash
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The release build is signed with the debug keystore (the Flutter default, left
in place for a proof of concept). Set up a real signing config in
`android/app/build.gradle.kts` before distributing anything.

### iOS — install on a real iPhone

Needs macOS; the app cannot be compiled for iOS from Linux.

1. ```bash
   cd app
   flutter pub get
   cd ios && pod install && cd ..
   ```
2. `open ios/Runner.xcworkspace` — in **Runner → Signing & Capabilities**, pick
   your Apple ID team. A free account is enough for a personal device; change
   the bundle identifier from `com.aiboxingcoach.boxingCoach` to something
   unique to you if Xcode complains it is taken.
3. Plug the iPhone in, trust the computer, select it as the run destination.
4. ```bash
   flutter run --release -d <iphone-id>
   ```
   or press ▶ in Xcode.
5. First launch on the device: Settings → General → VPN & Device Management →
   trust your developer certificate.

With a free Apple developer account the build expires after seven days and needs
reinstalling. `UIBackgroundModes: audio` is declared so cues keep playing with
the screen locked; `wakelock_plus` keeps the screen awake during a session.

---

## Decisions worth knowing about

**Device TTS rather than recorded audio.** The spec's open question 3 recommends
TTS for v1. It costs nothing, needs no network, and means the cue scripts can be
rewritten without re-recording anything — exactly right for a build whose job is
to find out whether the scripts are any good.

**Synthesised cue sounds.** `assets/audio/*.wav` are generated by
`tool/generate_cue_sounds.py`, not sampled from a real bell. They are clear
through a phone speaker in a noisy room. Swap in real recordings whenever
someone has them; nothing in the app cares where the samples came from.

**A `mobility` category, added to the spec's list.** The spec's thirteen
categories cover the boxing work but leave warm-up and cool-down exercises
untaggable, and an untagged exercise silently breaks category tracking.

**Category weights sum to one per exercise.** A three-minute round therefore
contributes three minutes of training load, split across what it develops,
rather than counting three minutes towards four different categories. A test
enforces it.

**The last rest of a phase is kept.** It is the transition into the next phase,
and it is where the coach previews what is coming.

**No session history.** Persistence belongs with the data model in v0.5. v0.1
storing sessions in a shape that the real schema then contradicts would be worse
than storing nothing.
