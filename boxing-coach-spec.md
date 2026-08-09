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
- **Backend-agnostic AI layer.** Adapter pattern lets us swap local models for API providers depending on device capability, privacy needs, and cost.

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
    ↓
Frame extraction (every 100ms, or keyframes on motion)
    ↓
Pose estimation (MediaPipe or MMPose)
    ↓ (33 keypoints per frame, tracked over time)
Motion analysis (rule-based)
    ↓ (guard position, punch retraction, stance, movement)
VLM analysis (sparing, for higher-level context)
    ↓ (e.g., "describe the last combination")
Feedback synthesis
    ↓
Delivered as audio between rounds
    ↓
Persisted with video for user review
```

### Model choices

**Pose estimation (v1):**
- **MediaPipe Pose** — fast, runs on-device, well-supported, adequate for gross motion
- **MMPose** with a trained model — more accurate but heavier, requires more setup
- Decision: start with MediaPipe, evaluate MMPose if accuracy insufficient

**VLM for context (v1):**
- **Local option:** Qwen2.5-VL 7B (Q4 quantised, ~10GB VRAM). Works offline, good privacy.
- **API options:** Claude 3.5 Sonnet vision, GPT-4o vision, Gemini 2.0 Flash
- Decision: adapter pattern lets us swap. Local for offline / privacy-focused users, API for capability / lower-hardware users.

**Realistic assessment:** general-purpose VLMs are not great at boxing-specific analysis without fine-tuning. Most of the useful signal in v1 comes from pose estimation + boxing-domain rules, with the VLM adding contextual descriptions rather than doing the primary analysis. Setting expectations here is important.

### Adapter interface

```python
class VisionAnalysisAdapter(ABC):
    @abstractmethod
    async def analyse_round(
        self,
        video_path: str,
        drill_context: DrillContext,
    ) -> RoundAnalysis:
        """
        Analyse a recorded round.
        drill_context tells the analyser what to look for
        (e.g., 'jab-focused drill, watch retraction and guard return').
        """
        pass


class LocalQwenAdapter(VisionAnalysisAdapter):
    """Runs Qwen2.5-VL locally alongside pose estimation."""
    pass


class ClaudeAdapter(VisionAnalysisAdapter):
    """Uses Claude's vision API for the VLM layer."""
    pass


class PoseOnlyAdapter(VisionAnalysisAdapter):
    """Fallback: pose estimation + rules only, no VLM.
    Fastest, most private, no external dependency."""
    pass
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
    adapter_used TEXT,  -- 'pose_only', 'local_qwen', 'claude', etc.
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

**Option A: fully local**
- Pose estimation on device
- Qwen2.5-VL 7B running on user's Mac/PC (via companion desktop app that phone syncs to for analysis)
- Best for privacy, cost, offline use
- Requires user has capable hardware

**Option B: hybrid**
- Pose estimation on device
- VLM analysis via API (Claude / GPT-4V / Gemini)
- Better analysis quality
- Costs per session (~€0.05-0.20 depending on provider and video length)
- Requires network

**Option C: pose-only**
- No VLM, just pose estimation + rules
- Fast, private, cheap
- Less rich feedback
- Fine for v0.5 / MVP

The adapter pattern lets users choose based on their situation.

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

1. **Companion desktop app for local VLM?** Adds complexity but is the only way local Qwen works with mobile phone recording. Alternative: cloud VLM as default, "advanced" users can wire up local.

2. **Recording storage duration.** Videos are sensitive (people don't want their sweaty bedroom sessions kept forever). Default policy: keep for 7 days, then delete unless user explicitly saves. Analysis persists.

3. **Coach voice.** Recorded human voice (higher quality, character) vs TTS (flexible, cheaper, easier updates). Recommend TTS with a good model (ElevenLabs or on-device) for v1, revisit for v2.

4. **Real-time cues during rounds.** Only reminders, not analysis. The coach speaks based on the drill/phase/timing, not based on what you're doing that instant. Real-time analysis adds latency without clear benefit.

5. **Session generation.** Do users pick from templates, generate custom, or does the AI suggest based on their weekly balance? Recommend: templates for MVP, AI-suggested v0.9, custom builder v1.

6. **Business model.** Free tier with basic timer + templates + pose-only analysis. Paid tier with VLM analysis, style coaching (v2), unlimited recording, etc. Or one-time purchase like traditional apps.

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

4. **Local Qwen requires a companion device.** Phones don't run 7B VLMs well yet. Realistic architecture: phone records, uploads to user's Mac/PC running local model, results come back. Adds complexity but preserves privacy story.

5. **Style differentiation is the marketing story but the hardest to deliver.** Being honest that v1 is "general amateur boxing" is better than shipping bad Mexican / Cuban / Soviet coaching that boxers will immediately dismiss.

6. **Injury and technique risk.** App can't stop a user hurting themselves. Include appropriate disclaimers, especially for high-intensity phases and for users who report joint pain in check-ins.

7. **This is a bigger project than the recovery app.** More moving parts, more expertise needed, higher stakes on the AI quality. Worth being realistic about scope and MVP.

---

## Suggested build sequence

Rather than everything at once:

**v0.1 (proof of concept):** Timer + basic coach cues + exercise library + session templates. No AI. Confirm the coaching UX works.

**v0.5:** Add recording and pose-only analysis. Ship the "MVP" listed above. This validates the core value proposition.

**v0.8:** Add VLM adapter (API-based first). Improved feedback quality. Beta with real boxers.

**v1.0:** Local model option. Session generation. Weekly reporting. Public launch.

**v2:** Style-specific coaching and analysis.

Ship each version to real users. Iterate on feedback. Don't try to build v2 before v0.5.
