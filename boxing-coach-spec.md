# AI Boxing Coach — App Specification (v1)

Personal training app that structures full boxing sessions, tracks progress per skill area, times rounds and rest periods with coach-style audio cues, and analyses technique from video during the technical portion using computer vision and AI models.

Emphasis on being a genuinely useful training tool, not gamified fitness content. Assumes the user is training seriously (like the actual user — amateur boxer, in a conditioning block, trains 2-3x/week).

---

## Design principles

- **Structured sessions over freestyle.** Every session has a defined arc (warm-up → conditioning → shadow → technical) with intent for each phase.
- **Progress tracking is category-based.** Individual exercises tagged with what they train (cardio, power, footwork, defence, combinations, head movement, distance management). Weekly view shows balance.
- **Coach behaviour is anticipatory.** The coach tells you what round you're in, what's coming next, gives cues at key moments, celebrates milestones. Not a passive timer.
- **Technical analysis is the differentiator.** Recording, form analysis, and specific corrections are what makes this different from a boxing timer app.
- **Style-aware coaching (v2).** v1 delivers competent general boxing coaching. v2 adapts to Mexican / Cuban / Soviet / American / European / Philippine styles.
- **Layered AI, cheapest-first.** Deterministic rules over on-device pose do the primary work; a swappable API model is an optional enrichment layer over the extracted data, never the foundation and never fed raw video.

---

## Session structure

Every full session follows this arc. Durations user-configurable within reasonable bounds.

### Phase 1: Warm-up (5-10 minutes)

Progressive activation. Never skipped.

- Joint mobility (neck, shoulders, hips, wrists, ankles)
- Light cardio (skipping, jogging in place, jumping jacks)
- Dynamic stretching
- Boxing-specific activation (light shadow with focus on movement, not power)

Coach cues: talking through what you're doing, why, and reminders about form even at low intensity.

### Phase 2: Conditioning (10-20 minutes)

Physical prep for the boxing work. Round-based structure emerging here.

- Rounds of 2-3 minutes, 30-60s rest
- Bodyweight work (push-ups, squats, burpees, planks, mountain climbers)
- Boxing conditioning (shadowboxing at moderate intensity, footwork drills)
- Optional equipment integration (medicine ball, resistance bands, kettlebell)

Coach cues: round announcements, halfway calls, "10 seconds left" warnings, rest countdown, next round preview.

### Phase 3: Shadow boxing (10-15 minutes)

Skill development without impact. Round-based.

- Rounds of 2-3 minutes, 30-60s rest
- Themed rounds: footwork focus, defence focus, combinations focus, jab focus, etc.
- Progressive intensity across rounds
- Includes movement patterns, not just striking

Coach cues: theme announcements, technique reminders during the round, ("keep the guard up", "step off the line", "double up the jab").

### Phase 4: Technical work (15-25 minutes)

**This is where the AI vision analysis happens.**

- Focused drill work on specific techniques
- Recording enabled
- Coach describes the drill and expected form
- Between rounds: video analysis produces feedback
- User can review specific frames flagged by the analysis

Coach cues: drill setup, technique reminders, post-round feedback based on analysis output.

### Phase 5: Cool-down (5-10 minutes)

Static stretching, breathing, session summary.

Coach cues: guided stretches, session recap, notable improvements, tomorrow's suggestion.

---

## Coach behaviour

The coach is not a passive timer. It behaves like an actual coach.

### Anticipatory cues

- 30 seconds before a round starts: "Get ready. Next round is footwork focus. Light on your feet."
- Start of round: "Round 3. Go."
- Halfway: "Halfway through. Keep the pace."
- 10 seconds left: "Ten seconds. Finish strong."
- Rest: "Rest. Breathe. Water if you need it."
- Round transitions: "Round 4 coming up. This one's power combinations."

### Technique reminders during rounds

Context-aware, based on the phase and drill:

- Shadow round themed "defence": "Slip after every combination", "Roll under the hook", "Head off the centre line"
- Technical round on jab: "Return to guard", "Push off the back foot", "Chin down"
- Conditioning round: "Breathe through your nose", "Stay tall", "Drive through the heels"

Cues are spaced (every 20-30 seconds) not constant. The coach doesn't talk over you.

### Milestone acknowledgement

- End of a round with visible improvement flagged by AI: "Better guard return that round. Keep it."
- End of session: "Solid session. You hit your conditioning target and your jab retraction was cleaner than last week."

### User-instigated logic

Some prompts require user action:

- "Ready for the next round?" (after long rest)
- "Camera check — can you see yourself in frame?" (before recording round)
- "How did that feel? 1-5" (post-round subjective effort)
- End of session: "Anything I should note for next time?"

---

## Category tracking

Every exercise, drill, and round is tagged with the skill areas it develops. Weekly and monthly views show balance.

### Categories tracked

- **Cardiovascular endurance** (conditioning rounds, high-tempo shadow)
- **Muscular endurance** (bodyweight conditioning, sustained combinations)
- **Power** (heavy shadow rounds, plyometrics, medicine ball)
- **Footwork** (movement drills, angle work, ring cutting)
- **Defence** (slipping, rolling, blocking, parrying drills)
- **Offence — jab** (jab-focused rounds, distance work)
- **Offence — straight** (cross, straight right/left)
- **Offence — hooks** (lead hook, rear hook)
- **Offence — uppercuts**
- **Combinations** (multi-punch sequences)
- **Head movement** (integrated with defence but tracked separately)
- **Distance management** (in-out, cutting angles, controlling range)
- **Rhythm and timing** (broken tempo drills, feints)

### Balance view

Weekly dashboard shows minutes/rounds per category. Highlights imbalances:

- "You've done 45 minutes of offensive combinations this week and 8 minutes of defensive work. Consider a defence-focused session next."
- "Footwork under-trained relative to your goal (competitive amateur). Suggested drill: ..."

---

## Timing and interval system

The core "timer" functionality but designed for how boxing actually works.

### Round configuration

- Standard: 3-minute rounds, 1-minute rest (competitive)
- Amateur: 2-minute rounds, 1-minute rest
- Training: 2-3 minute rounds, 30-60 second rest (configurable)
- Interval work: shorter bursts (30s work / 15s rest, tabata-style) for conditioning

### Audio cues

Distinct sounds for:
- Round start (bell)
- 30 seconds elapsed / 30 seconds remaining
- Halfway
- Last 10 seconds (tick-tick countdown)
- Round end (bell)
- Rest end / next round warning (short bell)

Volume and cue selection user-configurable.

### Visual timer

- Large, glanceable round clock
- Round number and phase indicator
- Current drill / theme
- Optional: heart rate display if paired with wearable

---

## Technical work — the AI vision layer

**This is the hard and important part. Being honest about what's realistic in v1.**

### Recording flow

1. User is prompted to set up phone/camera before the technical phase
2. Camera check confirms user is in frame (basic pose detection confirms full body visible)
3. Recording starts automatically at round start
4. Recording stops at round end
5. Analysis runs during the rest period
6. Feedback surfaced before next round (audio summary + optional detailed view)

### What gets analysed

For v1, focus on things that pose estimation + rule-based logic can reliably detect:

**Detectable in v1:**
- Guard position (are hands up at the end of combinations?)
- Return to guard after punching
- Chin position (up vs tucked)
- Basic stance (feet aligned correctly, weight distribution)
- Punch retraction (are punches returning to guard vs staying extended?)
- Head movement presence (is the head moving off the centre line at all?)
- Basic footwork (are steps happening, or is user rooted?)
- Off-balance moments (leaning too far forward on punches)

**Realistically v2 or requiring fine-tuning:**
- Style-specific critique ("your rear hand is dropping — Mexican style would keep it higher")
- Specific technique correctness ("your hook is at the wrong angle")
- Rhythm and timing analysis
- Intent recognition ("that was meant to be a feint but you committed to it")

**Not attempted:**
- Real-time in-round coaching (latency and UX both wrong)
- Fine-grained biomechanics without a trainer's judgment

### Vision pipeline architecture

```
Video capture (mobile camera)
    ↓  on-device
Frame sampling (~every 30-40ms)
    ↓  on-device
Pose estimation (MediaPipe)            ← the ONLY step that touches every frame
    ↓ (33 keypoints/frame → a few KB for the whole round; raw video never leaves here)
Rule engine (deterministic boxing logic)
    ↓ observations, metrics, flagged moments
Correction adjudication (API model, AMBIGUOUS flags only)
    ↓ (peak ± a sampled window of frames + pose context → confirm / soften / suppress)
Phrasing & summary (API model, structured data only — no pixels)
    ↓ (natural coaching language, session summary, trends)
Feedback synthesis
    ↓
Delivered as audio between rounds + optional detailed view
    ↓
Persisted (pose data always; video local by default, cloud opt-in)
```

Read the arrows as a cost gradient: everything above the rule engine runs locally at zero marginal cost, and the only things that ever reach a paid model are a few KB of structured data plus, for a handful of ambiguous moments, a few sampled frames. Video is never streamed to a model.

### Capture hardware — single camera in v1, multi-view 3D as the differentiator

**v1 baseline: one phone.** The recording flow above assumes a single mobile camera. This is the right starting point — no extra hardware, works with what the user owns — but it has one hard limitation worth stating plainly: a single camera is monocular. Depth (movement toward or away from the lens) is *estimated*, not measured. Anything that lives along the depth axis — hip and shoulder rotation on straight punches, front-to-back weight transfer — is the least reliable output. Front-on 2D simply cannot see it well.

**v2 differentiator: multi-view 3D.** Two or more cameras at distinct angles (e.g. ~45° and ~135°, or four around the athlete) recording the same round *simultaneously* can be fused into a true 3D skeleton by triangulation: run pose estimation on each view independently, then reconstruct each joint's 3D position from the known geometry between the cameras. This is a demonstrated technique, not a research gamble — Stanford's OpenCap produces markerless 3D biomechanics from two calibrated iPhones, validated against gold-standard marker-based systems, and has been run with four phones. With measured depth, the rotation- and balance-dependent rules move from "unreliable" to "trustworthy." This is the honest justification for any hardware play: not a *better* camera, but *more angles*.

**The two hard problems (neither is the camera):**

- *Calibration.* Triangulation needs to know where each camera sits relative to the others. A dead-simple, living-room-grade calibration flow is the difference between a product and a pile of parts — this is the core UX problem, not an implementation detail.
- *Synchronisation.* The views must be time-aligned, and boxing is unforgiving here: a jab lasts ~100–150ms, so even 30–40ms of drift between independent cameras smears the reconstruction of exactly the fast movements we care about. OpenCap's validated tasks (gait, squats, hops) are far slower; boxing is a harder sync problem than the existing literature has tackled. Prove sync tolerance on real punch footage early — it is the make-or-break for the whole rig.

**Chosen approach — dock-and-place, software-first (decisions).**

The instinct to solve sync and calibration with a rigid base where cameras sit while recording (a mat with retractable stands, or similar) is rejected: a mat shifts under a moving athlete and pins them to one spot, and a rigid rig is hard to manufacture, ship, store, and impossible to patch once it's in a living room. Instead, push the complexity out of hardware and into software — the right trade for a software-strong, hardware-light team, because auto-calibration is code we own and update over the air while the hardware stays cheap and flexible.

- **Dock, not a recording base.** The cameras live in a dock to charge, store, and stay clock-disciplined together. During a session they are *free-standing units the user places around the room* (tripod, shelf, wherever) — not fixed to a base. More flexible, nothing to slide underfoot.
- **Two cameras first; four later.** Front-left and front-right, quartering the athlete (~45° / ~135°), already removes the front-view depth blindness that motivates the whole rig. Fewer cameras are dramatically easier to place, sync, and auto-calibrate, so two is the first product; a four-camera "pro" tier follows once two-camera calibration is proven solid.
- **Calibration is split.** Lens *intrinsics* (fixed per camera) are calibrated once, at the factory/dock. Only the *extrinsics* — where each camera sits relative to the others — are solved per session, because the cameras move. This is the cost of dropping the rigid base: calibration becomes a per-session software step rather than a hardware constant.
- **Extrinsics auto-solve from the athlete's own body.** Every camera sees the same person; corresponding keypoints across views are enough to recover the relative camera poses by bundle adjustment. Flow: place the cameras roughly, stand in the capture volume for a few seconds, and the system triangulates *its own geometry* from your skeleton — no checkerboard, no wand. A guided fallback (hold a pose, turn slowly) covers shaky solves. Slightly less metrically precise than a printed target, but almost certainly good enough for technique analysis, and the UX is "put them down and stand there." **This is the single most important thing to prototype early — on a two-phone setup, before committing to any camera hardware.**
- **Wireless sync, high frame rate as the real lever.** No shared wire means no hardware trigger, so: one master (the phone or a designated master camera) broadcasts session start and a periodic resync beacon; each camera timestamps against a WiFi-disciplined clock; a shared visual event (a flash all cameras catch) at the top of each round refines alignment. Frame rate does the heavy lifting — **60fps floor, 120fps preferred** — so that one frame of residual misalignment is a few milliseconds, comfortably inside tolerance for a ~120ms punch. Intrinsics and clock discipline can be re-established while docked.
- **Each camera emits keypoints, not video.** Every camera runs pose estimation locally and sends only its skeleton (a few KB); the master fuses skeletons into 3D. Bandwidth stays trivial and the "never stream frames to a model" principle holds even at four cameras. BLE carries control, pairing, and (later) sensor telemetry — never video, which goes over WiFi.

**v3 — sensor fusion (IMU punch trackers).** Wrist-worn six-axis IMUs (the FightCamp / Hykso / POWA class: ~1000Hz, BLE, measuring punch count, type, speed, and power) are *complementary*, not redundant — cameras see form (guard, stance, head, posture) and are weak on dynamics; IMUs see dynamics and are blind to form. Fusion bonus: an IMU spike is a rock-solid timestamp-and-hand marker per punch, which feeds the vision punch-detector and *shrinks* the set of moments the AI has to adjudicate rather than growing it. Sync is not the obstacle — complexity scales with the number of independent *clocks*, not streams, so once everything references one master clock, adding the IMU stream is roughly linear, and BLE handles their tiny high-rate data easily. Deferred to a final phase for sequencing and focus reasons, not technical ones: don't add a second hardware stream before the first is proven, each device multiplies setup friction, and punch-metrics are a distinct value proposition (output/power, closer to FightCamp's territory) that would dilute the form-first story if pulled in early.

**Form-factor note — central-pole / panoramic camera.** An appealing idea is a single wide-angle or 360° camera on a mast (e.g. rising from a free-standing bag unit), seeing the athlete all the way around and steeply downward for footwork. Two cautions:

1. A single optical centre is still monocular no matter how wide the field of view. A 360° camera buys *coverage*, not *depth* — and cameras stacked on one thin pole share almost no baseline, so they don't triangulate well either. It does **not** replace spatially-separated cameras for 3D.
2. The steep top-down footwork view is optically the hardest angle there is: seeing the feet at the base and the torso above needs a fisheye, whose worst distortion sits exactly where the feet are; near-overhead angles are also out-of-distribution for pose models trained on horizontal views; and the athlete's own arms and shoulders occlude their feet while punching.

Where a central mast *does* earn its place is as a dedicated **overhead footwork camera**. Top-down is genuinely the best view for foot placement, stance width, weight shift, and pivoting — the things horizontal cameras see worst. Treat it as a complement feeding footwork-specific rules, dewarped, not as the primary body-analysis camera. (Also: if the mast is mounted on a bag that gets struck, impact shake will blur footage — a shadow-boxing station and a hit bag are different hardware requirements.)

**The free/paid split falls out of the hardware.** Single-camera 2D analysis can run on-device — the phone does pose estimation locally, at near-zero marginal cost — which makes a sustainable **free tier**, enough to feel the product. Multi-camera 3D needs calibration, sync, and cloud fusion: genuinely more valuable and genuinely more expensive to run, so it's the **paid tier**. The paywall sits exactly where both value and cost step up: front-view feedback free, true 3D technique scoring paid.

**Architecture impact: none downstream.** All of this lives behind the `PoseEstimator` seam. A `MultiViewPoseEstimator` consumes N calibrated, synchronised videos and emits the same `PoseSequence` type, now carrying measured 3D. Every rule and adapter above it is unchanged — the rotation rules simply get better because `z` is real. A top-down footwork camera is just another estimator feeding footwork rules. The rule engine never learns where the keypoints came from.

### Model choices

**Pose estimation — the workhorse.**
This is the one component that processes every frame, and it does so on-device, frame by frame, at zero marginal cost with nothing leaving the device. It compresses ~40,000 frames a session down to a few numbers per frame.
- **Decision: MediaPipe Pose.** Fast, on-device, adequate for gross motion. Evaluate MMPose only if MediaPipe's accuracy proves insufficient on real footage.
- Everything downstream consumes its keypoints, never raw video.

**The generative layer — optional, API-based, over extracted data.**
General-purpose models are not good at boxing-specific judgment without domain prompting and likely fine-tuning, and almost all of the useful v1 signal comes from pose + rules. So a generative model is a polish-and-adjudication layer, not the foundation: **v0.5 ships with none of it**, and it never sees raw video.
- **Decision: no local model.** The only things that ever leave the device are structured pose data (a few KB) and, for a few ambiguous moments, a handful of cropped keyframes. That privacy surface is tiny, so a hosted API is both cheaper and simpler than shipping and maintaining a quantised local model plus a companion device. (Local inference returns only if a fully-offline tier becomes a deliberate selling point — not a default.)
- **Decision: API provider sits behind the adapter** (Claude / Gemini / GPT-class). Swappable per job on cost and quality.

It has exactly two jobs, both over extracted data:
1. **Phrasing & summary (text-only, a fraction of a cent).** Turn structured observations into natural, varied coaching language; write session-level summaries; spot cross-session trends; answer the user's own questions ("why does my cross keep landing short?"). No pixels.
2. **Correction adjudication (a few images, gated).** Decide, for genuinely ambiguous flags, whether a deviation is a fault or a deliberate style — see next section.

**Cost principle (decision).** Extract on-device; never stream video or bulk frames to a paid model; text in / text out for phrasing; send pixels only for the few flagged windows that need them. Image tokens dominate cost, so the two dials are frame count and resolution — sample sparsely, downscale hard.

### Correction adjudication — style vs error

The single hardest judgment in the product is whether a flagged deviation is a genuine mistake or a deliberate stylistic choice. A low lead hand is a hole *or* a Philadelphia shell depending entirely on what the rest of the body is doing. This is the one place a generative model earns its keep over the rules — but only if the design is disciplined.

- **A window, not a frame.** A single frame can't distinguish style from error, because the discriminator lives in the motion and the whole-body context (is the low hand compensated — shoulder rolled, chin tucked behind it, head off-line, feet loaded — or just dropped?). For an ambiguous flag at peak time *t*, take a short window (roughly *t* − a few hundred ms to *t* + a few hundred ms) and **sample it sparsely** — every third frame, ~5-6 images. The arc and the compensation are visible; the cost isn't.
- **Gate hard — adjudicate only the ambiguous.** Most flags are certain and stay with the rules: a hand that drops to the hip after every punch is a hole, decided deterministically. Escalate to the model only when a rule fired *near its threshold*, or in a *style-sensitive* category (guard height, head position, hand carriage) — never the unambiguous ones (did the punch retract at all, are the feet moving). That's a handful of moments per session, not every flag.
- **Declared context first — cheapest of all.** If the user's profile or `DrillContext` declares a low-hand style, the rule **suppresses the flag itself** and no model is called. Order of defence: declared style → style-aware thresholds → model adjudication only for the residual "we don't know their intent" cases.
- **Clean frames + pose as text, not annotated pixels.** The reason to escalate is precisely that the skeleton discarded the cues that decide intent — glove orientation, chin behind the shoulder, actual posture. Painting the skeleton back onto the frame can occlude the very thing the model needs to see. Send clean frames plus the measured pose as structured text ("joints measured X, rule fired because Y — is this intentional?"). A/B clean-vs-annotated on known clips; the prior is clean-plus-numbers.
- **Determinism and trust.** Unlike the rules, a model's verdict varies run-to-run, and a correction that flip-flops erodes trust faster than one that's consistently wrong. Pin it down: low temperature, structured output (verdict enum + confidence + one-sentence reason), and surface the uncertainty in the UX ("this may be intentional — if you're working a shell guard, ignore it") rather than a hard ERROR.

**Decision:** correction adjudication is an API-based *enrichment* step that wraps deterministic output — it confirms, softens, or suppresses `Correction`s and `FlaggedMoment`s the rules already produced. It never originates them. The rules stay the honest backbone; the model only rules on close calls.

### Adapter interface

```python
class VisionAnalysisAdapter(ABC):
    @abstractmethod
    def analyse(self, sequence: PoseSequence, drill: DrillContext) -> RoundAnalysis:
        """Analyse a round from extracted pose (not raw video).
        drill tells the analyser what to look for and what style is declared."""


class PoseOnlyAdapter(VisionAnalysisAdapter):
    """Default (v0.5). Pose estimation + rules only. Deterministic, private, ~free.
    A complete, useful product on its own."""


class EnrichedAdapter(VisionAnalysisAdapter):
    """Wraps PoseOnlyAdapter, then calls an API model to (a) phrase and summarise
    and (b) adjudicate ambiguous flagged moments. Enriches, never originates.
    Constructed with a keyframe provider (source clip) so it can pull the
    sampled window for the few flags that need visual adjudication."""
```

The `RoundAnalysis` output is structured:

```python
@dataclass
class RoundAnalysis:
    overall_summary: str
    specific_observations: list[Observation]
    positive_notes: list[str]
    correction_priorities: list[Correction]
    metrics: RoundMetrics  # guard return %, punches thrown, etc.
    flagged_moments: list[FlaggedMoment]  # timestamps + reasons for user review


@dataclass
class Correction:
    priority: int  # 1 = most important
    category: SkillCategory
    description: str
    suggested_drill: str | None
    example_timestamp: float | None  # point to a specific moment in the video
```

---

## Boxing style (v2 aspiration, noted for design)

The style-based coaching feature deserves realistic scoping.

### The concept

User selects a preferred style. Coaching, drill selection, and analysis emphasise that style's characteristics.

- **Mexican:** aggressive pressure, body work, high volume, willing to trade
- **Cuban:** technical, angles, fast hands, controlled distance
- **Soviet:** fundamentals-heavy, defensive, sharp jab, hard to hit
- **American:** varied by era — modern is often boxer-puncher hybrid
- **European:** upright stance, long jab, distance control
- **Philippine:** speed, angles, unorthodox rhythm (per Pacquiao archetype)

### What v1 does

Ships with "general amateur boxing" as the coaching style. Well-rounded, no strong stylistic bias. Fine as a starting point for most users.

### What v2 requires

Actual boxing expertise embedded in the coaching logic. This means either:

- Working with a coach to write style-specific drill libraries, cueing scripts, and evaluation rules
- Fine-tuning a model on annotated video of different-style fighters (expensive, requires rights)
- Both

For v2, prioritise Mexican and Cuban first — most requested, most visually distinct, best documented in existing training material.

---

## Data model (SQLite, similar structure to recovery app)

```sql
-- Users, sessions, exercises, categories, rounds, analyses, corrections
-- Details similar in structure to the recovery app schema
-- Key tables:

CREATE TABLE users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    display_name TEXT,
    experience_level TEXT,  -- 'beginner', 'intermediate', 'advanced', 'competitive'
    preferred_style TEXT,   -- 'general' in v1, style key in v2
    training_goals TEXT,    -- JSON
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at DATETIME
);

CREATE TABLE skill_categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    key TEXT UNIQUE NOT NULL,
    label TEXT NOT NULL,
    parent_category_id INTEGER REFERENCES skill_categories(id)
);

CREATE TABLE exercises_catalog (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    key TEXT UNIQUE NOT NULL,
    label TEXT NOT NULL,
    description TEXT,
    default_duration_seconds INTEGER,
    phase TEXT,  -- 'warmup', 'conditioning', 'shadow', 'technical', 'cooldown'
    difficulty INTEGER,
    requires_equipment BOOLEAN,
    equipment_notes TEXT
);

CREATE TABLE exercise_category_map (
    exercise_id INTEGER NOT NULL REFERENCES exercises_catalog(id),
    category_id INTEGER NOT NULL REFERENCES skill_categories(id),
    weight REAL DEFAULT 1.0,  -- how much this exercise develops this category
    PRIMARY KEY (exercise_id, category_id)
);

CREATE TABLE session_templates (
    id TEXT PRIMARY KEY,  -- UUID
    user_id TEXT REFERENCES users(id),
    name TEXT NOT NULL,
    total_duration_minutes INTEGER,
    focus_area TEXT,  -- what this session emphasises
    style TEXT,       -- v2
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE session_instances (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    template_id TEXT REFERENCES session_templates(id),
    started_at DATETIME NOT NULL,
    completed_at DATETIME,
    total_duration_seconds INTEGER,
    perceived_effort INTEGER,  -- 1-10 RPE
    notes TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE session_rounds (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES session_instances(id) ON DELETE CASCADE,
    round_number INTEGER NOT NULL,
    phase TEXT NOT NULL,  -- 'warmup', 'conditioning', etc.
    exercise_id INTEGER REFERENCES exercises_catalog(id),
    duration_seconds INTEGER,
    rest_seconds INTEGER,
    theme TEXT,  -- e.g., 'footwork', 'defence', 'jab focus'
    was_recorded BOOLEAN DEFAULT 0,
    recording_path TEXT,
    perceived_effort INTEGER,
    started_at DATETIME,
    completed_at DATETIME
);

CREATE TABLE round_analyses (
    id TEXT PRIMARY KEY,
    round_id TEXT NOT NULL REFERENCES session_rounds(id) ON DELETE CASCADE,
    adapter_used TEXT,  -- 'pose_only' (free) or 'enriched' (API), etc.
    analysed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    overall_summary TEXT,
    metrics_json TEXT,  -- structured metrics
    processing_time_ms INTEGER
);

CREATE TABLE round_corrections (
    id TEXT PRIMARY KEY,
    analysis_id TEXT NOT NULL REFERENCES round_analyses(id) ON DELETE CASCADE,
    priority INTEGER NOT NULL,
    category_id INTEGER REFERENCES skill_categories(id),
    description TEXT NOT NULL,
    suggested_drill_id INTEGER REFERENCES exercises_catalog(id),
    example_timestamp_ms INTEGER,  -- where in the video this happens
    was_addressed BOOLEAN DEFAULT 0  -- did user acknowledge / work on it?
);

CREATE TABLE round_observations (
    id TEXT PRIMARY KEY,
    analysis_id TEXT NOT NULL REFERENCES round_analyses(id) ON DELETE CASCADE,
    timestamp_ms INTEGER NOT NULL,
    observation_type TEXT,  -- 'guard_drop', 'chin_up', 'balance', 'good_footwork', etc.
    severity TEXT,  -- 'positive', 'minor', 'moderate', 'major'
    description TEXT
);
```

---

## Technical architecture summary

### Client (mobile app)

- **iOS/Android native** (React Native or Flutter for shared codebase) — camera access, audio, background timers, offline capable
- **Timer and coach engine** runs locally, no network required
- **Video capture** runs locally
- **Pose estimation** runs locally (MediaPipe has good mobile SDKs)

### AI processing options

The cost model is fixed by one rule: heavy work stays local, and the paid model only ever sees small extracted data.

**On-device, every session (free tier):** frame sampling + MediaPipe pose + the rule engine. No network, no per-session cost. This is a complete, useful product on its own — it's what `PoseOnlyAdapter` ships.

**API, when enabled (paid tier):** phrasing and summary over structured data (text-only, a fraction of a cent) plus correction adjudication over a few sampled keyframes, for ambiguous flags only. Bounded cost — a handful of small calls per session, dominated by a few downscaled images rather than video. Rough order: comfortably under €0.05/session, versus the per-session blow-up you'd get streaming frames (explicitly not done).

**Never:** stream video or bulk frames to a paid model; run a self-hosted model / companion-device path. The latter was considered and dropped — once only pose data and a few crops ever leave the device, the privacy gain doesn't justify the local-inference and companion-hardware complexity.

**Multi-camera 3D (v2)** is the one place video does go to the cloud — calibration, sync, and triangulation need server-side fusion. That cost lives in the same tier as the hardware that creates it, which is why the paywall and the cloud bill both sit at the 3D tier.

The adapter pattern means the free and paid tiers are the same pipeline with the enrichment step turned off or on — not two codebases.

### Backend

- Session data syncs to a lightweight backend (Supabase, Firebase, or self-hosted)
- User can export their data anytime
- Videos stored locally by default, cloud upload opt-in
- If cloud storage used, encrypted at rest

---

## MVP scope (what ships first)

Cutting hard:

- Sessions with warm-up + conditioning + shadow + technical + cool-down
- Round timer with coach cues (audio, English only for MVP)
- Exercise library covering all phases with category tags
- Weekly category balance dashboard
- Video recording during technical rounds
- Pose estimation on device (MediaPipe)
- Rule-based analysis for: guard return, punch retraction, basic stance, head movement presence
- Structured feedback delivered as audio between rounds
- Session history

Explicitly deferred to later versions:

- VLM integration (v0.9 / v1.1)
- Style-specific coaching (v2)
- Style-specific analysis (v2)
- Multi-language coach (v2)
- Wearable integration (v2)
- Social features (never, unless there's a real reason)

---

## Open questions worth deciding before build

1. **Adjudication quality without fine-tuning.** The style-vs-error call is the riskiest AI dependency. Open: how far a well-prompted general API model gets on real clips before boxing-specific fine-tuning (or a small labelled dataset of known style-vs-error examples) becomes necessary. Decide by prototyping on footage where the answer is known — not in front of users.

2. **Recording storage duration.** Videos are sensitive (people don't want their sweaty bedroom sessions kept forever). Default policy: keep for 7 days, then delete unless user explicitly saves. Analysis persists.

3. **Coach voice.** Recorded human voice (higher quality, character) vs TTS (flexible, cheaper, easier updates). Recommend TTS with a good model (ElevenLabs or on-device) for v1, revisit for v2.

4. **Real-time cues during rounds.** Only reminders, not analysis. The coach speaks based on the drill/phase/timing, not based on what you're doing that instant. Real-time analysis adds latency without clear benefit.

5. **Session generation.** Do users pick from templates, generate custom, or does the AI suggest based on their weekly balance? Recommend: templates for MVP, AI-suggested v0.9, custom builder v1.

6. **Business model.** Free tier = timer + templates + on-device pose-only analysis (single camera). Paid tier = API enrichment (natural phrasing, summaries, correction adjudication), and later multi-camera 3D + style coaching (v2). The free/paid line follows the cost gradient: on-device is ~free, API and cloud fusion cost money. Open: subscription vs one-time, and whether the 3D hardware is a bundle (see capture-hardware section).

---

## What makes this different from existing apps

For context, existing options include:

- **Boxing timer apps** (endless, all basically the same) — just timers, no coaching
- **Fight Camp / Liteboxer** — hardware-tied, expensive, focused on entertainment
- **Titan Boxing** — fitness classes, not skill development
- **Anthony Alvarado's app** — real coaching content but not interactive
- **PunchLab, Everlast apps** — mixed quality, generally shallow

The differentiator here is:

1. **Actual technical analysis via camera** — nothing else does this well at consumer price point
2. **Category-balanced session tracking** — treats boxing training like serious training, not gamified fitness
3. **Style-aware coaching (v2)** — real coaches do this; software doesn't
4. **Structured sessions with real coach behaviour** — anticipatory cues, not just timers

The market is meaningful:
- Amateur boxers training at home or in gyms without dedicated coaches
- Recreational boxers who want structure
- Boxing gym members who want to supplement gym time with focused solo work
- Coaches who want to give students structured homework

---

## Honest constraints and risks

1. **The vision analysis quality is the entire product's credibility.** If corrections are wrong, users lose trust immediately. Better to under-promise and over-deliver — start with fewer, more reliable observations rather than trying to catch everything.

2. **Boxing expertise is required to build this well.** Working with an actual boxing coach (not just a fitness coach) is essential for the drill library, cueing scripts, and evaluation rules. This isn't a nice-to-have.

3. **Camera setup will frustrate users.** The instructions matter enormously. Consider: pre-flight camera check with visual feedback, saved setup for repeat sessions, angle guidance.

4. **Style-vs-error is the hardest judgment, and it's the one non-deterministic call.** Deciding whether a deviation is a fault or a deliberate style is expert-coach territory, and a general API model will be mediocre at it without boxing-specific prompting and probably fine-tuning. Two failure modes: being wrong, and being *inconsistent* (a correction that flips between runs erodes trust faster than a steady wrong one). Mitigate with declared-style suppression first, hard gating to ambiguous flags, low-temperature structured output, and honest uncertainty in the UX. Prototype on known-answer clips before shipping.

5. **Cost discipline is a design constraint, not an optimisation.** The moment the pipeline streams video or bulk frames to a paid model, per-session economics break. The architecture must keep heavy work on-device and send the model only structured data plus sparse, downscaled keyframes for gated flags. Any feature that would regress this needs to justify itself against the unit cost.

6. **Style differentiation is the marketing story but the hardest to deliver.** Being honest that v1 is "general amateur boxing" is better than shipping bad Mexican / Cuban / Soviet coaching that boxers will immediately dismiss.

7. **Injury and technique risk.** App can't stop a user hurting themselves. Include appropriate disclaimers, especially for high-intensity phases and for users who report joint pain in check-ins.

8. **This is a bigger project than the recovery app.** More moving parts, more expertise needed, higher stakes on the AI quality. Worth being realistic about scope and MVP.

---

## Suggested build sequence

Rather than everything at once:

**v0.1 (proof of concept):** Timer + basic coach cues + exercise library + session templates. No AI. Confirm the coaching UX works.

**v0.5:** Add recording and pose-only analysis. Ship the "MVP" listed above. This validates the core value proposition.

**v0.8:** Add the API enrichment adapter — phrasing/summaries first, then correction adjudication over gated, sampled keyframes. Beta with real boxers to calibrate rule thresholds and test the style-vs-error verdicts on known clips.

**v1.0:** Enrichment on by default for the paid tier. Session generation. Weekly reporting. Public launch.

**v2:** Multi-view 3D capture — a two-camera dock-and-place rig with per-session auto-calibration from body pose, unlocking reliable rotation/depth analysis and the paid hardware tier. Only after single-camera feedback has proven it resonates, and only after the auto-calibration is validated on a two-phone prototype. Four-camera "pro" tier once two-camera calibration is solid.

**v3:** Sensor fusion — wrist IMU punch trackers fused with the vision rig for punch dynamics (count, type, speed, power), using the master clock already established for the cameras. Last, deliberately: a second hardware stream only after the first earns its place.

Ship each version to real users. Iterate on feedback. Don't try to build v2 before v0.5.