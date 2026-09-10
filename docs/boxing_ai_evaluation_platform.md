# Boxing AI Evaluation Platform

## Technical Design Document

**Status:** Initial blueprint\
**Purpose:** Build a repeatable system for improving the accuracy,
consistency and usefulness of the AI boxing analysis without relying on
subjective iteration.

------------------------------------------------------------------------

## 1. Goal

The objective is not simply to add more app features. It is to create an
**evaluation and continuous-improvement system** for the boxing-analysis
engine.

Every change should answer:

> **Did this version actually become a better boxing coach?**

### Core principles

1.  Every improvement must be measurable.
2.  Every model, prompt and pipeline version must be reproducible.
3.  Every benchmark dataset must be versioned.
4.  Ground truth comes from human/coach judgement, not from the model
    grading itself.
5.  A candidate should not replace production unless it performs better
    on agreed criteria.
6.  Improving one area must not silently make another worse.
7.  Automation can propose and test improvements; humans retain
    promotion control.

------------------------------------------------------------------------

## 2. High-Level Architecture

``` text
Benchmark Videos + Coach Labels
              |
              v
       Video Processing
              |
              v
       Pose / Motion Layer
              |
              v
      Feature Engineering
              |
              v
         Coaching AI
              |
              v
      Evaluation Engine <---- Ground Truth
              |
              v
       Metrics / Reports
              |
              v
      Continuous Improvement
     candidate -> test -> gate
```

The **evaluation engine is the centre of the system**. Pose estimation,
feature extraction and AI reasoning can all change while the benchmark
provides a stable way to decide whether a change is genuinely better.

------------------------------------------------------------------------

## 3. Benchmark Dataset

Build a curated collection of videos against which every candidate
version is tested.

### Dataset composition

Include deliberate variety:

-   Beginners, intermediate and advanced boxers
-   Orthodox and southpaw
-   Different heights/body types
-   Shadow boxing
-   Heavy-bag work
-   Technical drills
-   Combination work
-   Different camera positions
-   Different lighting/backgrounds/devices
-   Correct technique
-   Obvious errors
-   Subtle errors
-   Multiple simultaneous errors

Avoid a benchmark made only of easy examples.

### Initial size

``` text
Phase 1       25–50 carefully labelled clips
Phase 2       100–250 clips
Phase 3       500+ clips/segments
Production    Continuously expanding regression suite
```

Quality of annotation matters more than quantity initially.

### Dataset separation

``` text
development/  Used while designing improvements
validation/   Used to compare candidates
golden/       Protected final benchmark
```

Do not repeatedly optimise directly against the protected golden set.

------------------------------------------------------------------------

## 4. Ground-Truth Annotation

For every benchmark clip, store what a competent boxing coach believes
actually happened.

Example:

``` yaml
video_id: jab_cross_017
stance: orthodox
exercise: jab_cross
skill_level: beginner

observations:
  - id: rear_heel_rotation
    present: false
    severity: major
    confidence: high

  - id: chin_exposure
    present: true
    severity: medium
    confidence: high

  - id: lead_hand_return
    present: true
    severity: minor
    confidence: medium

positive_observations:
  - good_extension_on_jab
  - balanced_starting_stance

priority_feedback:
  1: rear_heel_rotation
  2: chin_exposure
  3: lead_hand_return
```

This creates structured truth rather than merely storing free-form
coaching paragraphs.

### Annotation tools

Potential options:

-   **Label Studio**
-   **CVAT**
-   Eventually, a small custom boxing-specific annotation UI

Some clips should eventually be reviewed by multiple knowledgeable
reviewers so genuine ambiguity can be distinguished from model error.

------------------------------------------------------------------------

## 5. Boxing Technique Taxonomy

Create a stable taxonomy of observations.

``` text
STANCE
- stance_width
- weight_distribution
- balance
- foot_orientation

GUARD
- chin_position
- lead_hand_position
- rear_hand_position
- elbow_position

PUNCH MECHANICS
- shoulder_rotation
- hip_rotation
- rear_heel_rotation
- extension
- elbow_path
- wrist_alignment
- hand_return

MOVEMENT
- crossing_feet
- stance_recovery
- lateral_balance
- forward_balance
- backward_balance

BODY POSITION
- excessive_lean
- upright_posture
- head_position
- centre_of_mass

DEFENCE
- guard_recovery
- head_movement
- defensive_position_after_punch
- exposure_during_combination

TIMING / COMBINATIONS
- rhythm
- pauses
- sequencing
- reset_time
- combination_flow
```

A stable taxonomy makes automated evaluation much easier than comparing
unrestricted prose.

------------------------------------------------------------------------

## 6. Pose and Motion Layer

Convert video into measurable body movement.

Potential approaches:

-   MediaPipe Pose
-   RTMPose
-   YOLO/person tracking + pose estimation
-   Other pose models as experiments warrant

Do not permanently couple the rest of the system to one provider.
Normalise pose output into an internal schema.

Example:

``` json
{
  "frame": 132,
  "timestamp_ms": 4400,
  "keypoints": {
    "left_shoulder": [0.42, 0.31, 0.97],
    "right_shoulder": [0.55, 0.32, 0.98],
    "left_hip": [0.45, 0.57, 0.95]
  }
}
```

This lets you benchmark different visual pipelines independently of the
coaching layer.

------------------------------------------------------------------------

## 7. Feature Engineering

Convert raw landmarks into boxing-relevant signals wherever practical.

### Geometric features

-   shoulder angle
-   hip angle
-   elbow angle
-   knee flexion
-   stance width
-   head displacement
-   torso inclination
-   hand-to-chin distance

### Temporal features

-   punch start/end
-   peak extension
-   hand-return time
-   rotation timing
-   foot rotation relative to punch
-   combination spacing
-   recovery time

### Movement features

-   centre-of-mass approximation
-   forward/backward drift
-   lateral displacement
-   stance recovery
-   balance after punch
-   foot crossing

### Derived boxing events

``` text
jab_started
jab_peak_extension
jab_retracted
cross_started
rear_hip_rotation_started
rear_heel_rotation_started
guard_recovered
stance_recovered
```

This also makes errors diagnosable: pose error, feature error,
event-segmentation error or coaching-reasoning error.

------------------------------------------------------------------------

## 8. Coaching AI

Separate:

``` text
DETECTION: What happened?
COACHING:  What does it mean and what should the boxer do?
```

Example intermediate output:

``` json
{
  "detected_issues": [
    {
      "type": "rear_heel_rotation",
      "severity": "major",
      "confidence": 0.91,
      "evidence": {
        "rotation_degrees": 4.2
      }
    }
  ]
}
```

The coaching layer then converts evidence into concise, actionable
feedback.

Separating detection from explanation makes both much easier to
evaluate.

------------------------------------------------------------------------

## 9. Evaluation Engine

For each clip compare the AI's structured observations with ground
truth.

### Detection metrics

-   **True Positive:** correctly detects a real issue
-   **False Positive:** claims an issue that is not present
-   **False Negative:** misses a real issue
-   **True Negative:** correctly avoids inventing an issue

``` text
Precision = TP / (TP + FP)
Recall    = TP / (TP + FN)
F1        = 2 × Precision × Recall / (Precision + Recall)
```

### Coaching-specific metrics

Also track:

-   unsupported-claim/hallucination rate
-   severity accuracy
-   priority-ranking accuracy
-   confidence calibration
-   positive-technique recognition
-   repeated-run consistency
-   usefulness/actionability
-   excessive-feedback rate

The aim is not maximum feedback. It is **accurate, prioritised and
useful feedback**.

------------------------------------------------------------------------

## 10. Weighted Boxing Score

Not all errors matter equally.

Example:

``` text
Major issue     weight 5
Medium issue    weight 3
Minor issue     weight 1
```

A falsely reported major flaw should also cost more than an unnecessary
minor suggestion.

Final weighting should eventually be validated with real boxing coaches
rather than chosen only mathematically.

------------------------------------------------------------------------

## 11. Per-Category Scores

Never rely only on a global score.

Track:

-   Overall
-   Punch mechanics
-   Guard
-   Balance
-   Footwork
-   Rotation
-   Body position
-   Defence
-   Timing
-   Combination analysis
-   Shadow boxing
-   Bag work

Example:

``` text
Overall F1     0.87 -> 0.89  PASS?
Footwork F1   0.91 -> 0.78  REGRESSION
```

The candidate may still need rejection despite a higher overall score.

------------------------------------------------------------------------

## 12. Experiment Tracking

Every evaluation run should record:

``` yaml
experiment_id:
timestamp:
dataset_version:
pose_model:
pose_model_version:
feature_pipeline_version:
coaching_model:
model_parameters:
system_prompt_version:
analysis_prompt_version:
code_commit:

metrics:
  overall_precision:
  overall_recall:
  overall_f1:
  hallucination_rate:
  severity_accuracy:

category_metrics:
  footwork:
  rotation:
  guard:
  balance:
```

Potential tools:

-   MLflow
-   Weights & Biases
-   LangSmith, particularly for LLM-heavy evaluation

Choose tooling after the simple benchmark works.

------------------------------------------------------------------------

## 13. Continuous Improvement Loop

``` text
Current Production Version
          |
          v
Identify Weakest Category
          |
          v
AI proposes ONE targeted change
          |
          v
Run Full Benchmark
          |
          v
Better overall + no unacceptable regression?
        /         NO     YES
      |       |
   Reject   Human Review
              |
              v
           Promote
```

The benchmark, not the optimisation AI, determines whether the candidate
improved.

------------------------------------------------------------------------

## 14. Automated Candidate Generation

Eventually an optimisation agent can receive:

1.  Current configuration
2.  Benchmark results
3.  Failure examples
4.  Category metrics
5.  Experiment history

Example task:

``` text
Current production version:

Footwork recall: 0.71
Footwork precision: 0.92

Analyse the false-negative examples.

Propose ONE change intended to improve footwork recall without
reducing precision below 0.90 or reducing another major category
beyond the permitted regression threshold.

Return:
- hypothesis
- proposed change
- expected effect
- affected components
```

Then benchmark the candidate automatically.

**Do not let an AI simply grade its own prose and declare itself
improved.**

------------------------------------------------------------------------

## 15. Promotion Gates

Define explicit criteria.

Example:

``` text
Candidate can progress only if:

✓ Overall weighted score improves
✓ Hallucination rate does not increase
✓ No critical category exceeds regression tolerance
✓ Major-error recall remains above threshold
✓ Output-schema tests pass
✓ Runtime remains acceptable
✓ Cost per analysis remains acceptable
```

Then:

``` text
AUTOMATED BENCHMARK
        |
        v
CANDIDATE PASSES
        |
        v
HUMAN SAMPLE REVIEW
        |
        v
STAGING / SHADOW TRAFFIC
        |
        v
PRODUCTION
```

Do not initially allow an optimiser to deploy directly to production.

------------------------------------------------------------------------

## 16. Nightly Evaluation

Once stable:

``` text
02:00
  |
  v
Run candidate against benchmark
  |
  v
Calculate metrics
  |
  v
Compare with production
  |
  v
Generate regression report
  |
  v
Store experiment
  |
  v
Notify on significant improvement,
regression or evaluation failure
```

This removes the need to manually watch the same clips after every
change.

------------------------------------------------------------------------

## 17. Human Coach Review

Automated metrics cannot fully decide whether something is good
coaching.

Periodically sample analyses and score:

``` text
Technical correctness        1–5
Importance prioritisation    1–5
Clarity                      1–5
Actionability                1–5
Evidence                     1–5
Appropriate confidence       1–5
Overall coaching quality     1–5
```

Also ask:

-   Did it miss anything important?
-   Did it invent anything?
-   Would you give this feedback to the boxer?
-   What would you prioritise differently?

These reviewed examples can strengthen future evaluation data.

------------------------------------------------------------------------

## 18. Regression Dataset

Every important discovered failure should become a permanent test.

Example:

A southpaw cross is analysed incorrectly because the system assumes
orthodox stance.

Once fixed, add that authorised test case to:

``` text
datasets/regressions/stance/
```

Every future candidate must pass it.

The system should learn both **how to improve** and **how not to repeat
old mistakes**.

------------------------------------------------------------------------

## 19. Production Feedback Loop

Eventually:

``` text
Real user session
      |
      v
Analysis
      |
      v
User/coach feedback
      |
      v
Interesting failure?
      |
      v
Human verification
      |
      v
Authorised benchmark/regression example
```

Do not automatically treat user feedback as truth.

Privacy, consent, retention and deletion rules should be explicit before
customer videos are reused for model/evaluation improvement.

------------------------------------------------------------------------

## 20. Suggested Repository Structure

``` text
boxing-ai/
|
├── datasets/
│   ├── development/
│   ├── validation/
│   ├── golden/
│   └── regressions/
|
├── annotations/
│   ├── taxonomy/
│   └── schemas/
|
├── pose/
│   ├── providers/
│   └── normalisation/
|
├── features/
│   ├── geometry/
│   ├── temporal/
│   └── boxing/
|
├── coaching/
│   ├── prompts/
│   ├── schemas/
│   └── reasoning/
|
├── evaluation/
│   ├── metrics/
│   ├── scorers/
│   ├── runners/
│   └── promotion/
|
├── experiments/
├── reports/
|
├── automation/
│   ├── nightly/
│   └── candidate_generation/
|
├── tests/
│   ├── unit/
│   ├── integration/
│   └── regressions/
|
└── docs/
    └── BOXING_AI_EVALUATION_PLATFORM.md
```

------------------------------------------------------------------------

## 21. Versioning

A production analysis should be uniquely reconstructable.

``` text
Boxing Analysis v1.14.3

Pose:             RTMPose X
Feature pipeline: features-v17
Technique taxonomy: taxonomy-v5
Prompt:           coach-v31
Model:            model-x
Benchmark:        golden-v8
Git:              8f219ae
```

If quality changes unexpectedly, you should be able to reproduce exactly
what generated an old result.

------------------------------------------------------------------------

## 22. Example Evaluation Report

``` text
Candidate: coach-v32
Baseline:  coach-v31
Dataset:   golden-v8

                         BASE       CANDIDATE
Overall Precision        91.2%      92.1%   ↑
Overall Recall           84.7%      88.4%   ↑
Overall F1               87.8%      90.2%   ↑
Hallucination Rate        4.8%       3.9%   ↓
Severity Accuracy        86.1%      87.0%   ↑

Rotation F1              91.0%      94.2%   ↑
Guard F1                 90.1%      90.3%   →
Footwork F1              82.4%      87.7%   ↑
Balance F1               88.7%      88.4%   →

Major regressions: NONE

Recommendation:
PASS TO HUMAN REVIEW
```

This is the eventual goal: objective evidence rather than personally
re-reviewing every clip after every change.

------------------------------------------------------------------------

## 23. Recommended Implementation Order

### Phase 1 --- Establish truth

-   Define technique taxonomy
-   Select 25--50 representative clips
-   Manually annotate them
-   Define structured analysis output
-   Write simple comparison/evaluation scripts

**Outcome:** You can measure whether V2 is actually better than V1.

### Phase 2 --- Reproducible benchmarking

-   Version datasets
-   Store experiments
-   Add category metrics
-   Add regression tests
-   Generate comparison reports automatically

**Outcome:** Every analysis change has evidence behind it.

### Phase 3 --- Improve visual understanding

-   Standardise pose representation
-   Build boxing-specific derived features
-   Compare pose/model alternatives
-   Add temporal/event detection

**Outcome:** Coaching increasingly rests on measurable movement rather
than model intuition.

### Phase 4 --- Human-quality evaluation

-   Recruit knowledgeable boxing reviewers
-   Double-label ambiguous examples
-   Build coaching-quality rubric
-   Expand golden dataset

**Outcome:** Benchmark increasingly represents genuine coaching quality.

### Phase 5 --- Automated optimisation

-   Identify weak categories automatically
-   Let AI propose targeted changes
-   Run candidates automatically
-   Reject regressions automatically
-   Send successful candidates for human review

**Outcome:** Much of the iteration loop operates without you.

### Phase 6 --- Production learning

-   Capture authorised real-world failure examples
-   Add verified failures to regression suite
-   Monitor production quality
-   Use shadow/canary evaluation before major releases

**Outcome:** The app becomes progressively harder to break and better
informed by real usage.

------------------------------------------------------------------------

## 24. What Not to Automate Initially

Avoid starting with:

``` text
AI watches random videos
→ judges its own answers
→ rewrites its own prompt
→ deploys itself
```

That can produce apparent improvement without real improvement.

Start with:

``` text
TRUSTWORTHY BENCHMARK
        +
STRUCTURED GROUND TRUTH
        +
REPEATABLE METRICS
```

Once those exist, aggressive automation becomes much safer.

------------------------------------------------------------------------

## 25. Immediate MVP

The smallest useful implementation does **not** require MLflow, DVC,
CVAT, multiple pose models and an autonomous optimiser on day one.

Build this first:

``` text
1. 30 representative boxing clips

2. One JSON ground-truth file per clip

3. Stable taxonomy of ~20–40 technique observations

4. Command:
      evaluate-analysis

5. For every clip:
      run current analysis
      compare detections with labels

6. Output:
      precision
      recall
      F1
      false positives
      false negatives
      category breakdown

7. Save:
      model
      prompt/version
      git commit
      score

8. Compare:
      CURRENT vs CANDIDATE
```

That alone changes the process from:

> "I changed the analysis and it looks better."

to:

> "Candidate V9 increased major-technique recall from 81% to 89%,
> reduced false positives from 7% to 4%, and caused no category
> regression."

------------------------------------------------------------------------

## 26. North-Star Architecture

``` text
REAL BOXING DATA
       |
       v
VERIFIED GROUND TRUTH
       |
       v
VERSIONED GOLDEN DATASET
       |
       v
ANALYSIS PIPELINE
Pose -> Features -> Detection -> Coaching AI
       |
       v
EVALUATION ENGINE
       |
       +-------------------+
       |                   |
       v                   v
Failure Analysis      Quality Metrics
       |                   |
       +---------+---------+
                 |
                 v
        OPTIMISATION AGENT
                 |
                 v
         CANDIDATE VERSION
                 |
                 v
          FULL BENCHMARK
                 |
          +------+------+
          |             |
          v             v
      REGRESSION    IMPROVEMENT
          |             |
          v             v
        REJECT      HUMAN REVIEW
                        |
                        v
                   PRODUCTION
                        |
                        v
                REAL-WORLD FAILURES
                        |
                        +--> VERIFIED REGRESSION DATA
```

The long-term goal is **not a model that magically trains itself**.

It is a controlled system in which:

> **AI can iterate extremely quickly, while objective benchmarks and
> human boxing expertise determine what counts as improvement.**

That gives you a path toward an analysis engine that becomes
progressively more accurate without requiring you to personally
supervise every iteration.

