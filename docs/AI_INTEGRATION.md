# AI integration

The optional vision-language layer that phrases sharper coaching on top of the
on-device analysis. It is **additive**: no model, no key, or no network still
leaves a complete offline analysis ([`POSE_ANALYSIS.md`](POSE_ANALYSIS.md)).
Coaching is never a blocker.

Code: `app/lib/services/ai/`, `app/lib/analysis/analysis_mode.dart`,
`app/lib/services/round_analyzer.dart`.

## Analysis modes

Chosen in the profile, applied to every technical round
(`analysis/analysis_mode.dart`):

| Mode | `value` | What runs | Cost |
| --- | --- | --- | --- |
| **Offline** | `offline` | Pose + rules on-device. The default and the whole of v0.5. | Free, offline, private. |
| **Pose + AI on key moments** | `keyframe` | Offline first, then a model reviews the handful of frames the rules flagged (plus the pose read as text). | A few frames per round. |
| **Full AI review** | `full_frame` | A vision model watches frames sampled across the whole round. | Richest, most expensive. |

`AnalysisMode.usesAi` is true for anything but offline. `full_frame` is
`available == false` — parked behind a "Coming soon" badge until the self-hosted
vision endpoint lands. Its pipeline is kept intact, just not selectable.

## The vision-model seam

The coaching pipeline talks only to the `VisionModel` interface
(`ai/vision_model.dart`), so the concrete provider is a swap of implementation:

- **`VisionRequest`** — system prompt, user prompt, images, `maxTokens` (default
  1200 — headroom so a full read isn't cut off, and thinking models can spend
  part of it reasoning), `temperature` (0.4).
- **`VisionImage`** — JPEG/PNG bytes + mime.
- **`VisionModelException`** — thrown when the model can't be reached or errors.
  The pipeline treats it as "no AI enrichment this round", never a broken
  session.

### OpenAI-compatible implementation

`OpenAiCompatibleVisionModel` (`ai/openai_compatible_vision_model.dart`) speaks
the OpenAI `/chat/completions` protocol with image content parts. It works
unchanged against OpenAI, DashScope (Qwen), OpenRouter, Together, or a
self-hosted vLLM/TGI server — **only the config changes**.

`VisionModelConfig` (`ai/vision_model_config.dart`):

- `baseUrl` — the OpenAI-compatible base ending in `/v1`
  (`https://api.openai.com/v1`, DashScope's compatible-mode URL for Qwen, or
  `http://<host>:8000/v1` for local vLLM);
- `apiKey` — bearer token; empty is allowed for a local endpoint;
- `model` — model id (`gpt-4o-mini`, `qwen3-vl-8b-instruct`, …).

`isConfigured` is true once there's a base URL and a model. Moving from "test
against an API" to "run my own model" is a change of `baseUrl` + `model`,
nothing else. Config is persisted by `ai_settings_store.dart`. `buildBody()` is
exposed so tests pin the exact wire shape.

## Prompt & frame selection

`CoachingPrompt` (`ai/coaching_prompt.dart`) is pure — the prompt shape and
which frames get sent are unit-tested without a model.

- **System prompt** casts the model as a sharp, experienced coach: short, direct
  voice, confirm what's good, then the corrections — no preamble, no numbered
  essays.
- **Keyframe bursts.** For each moment the rules flagged, `keyframeBursts()`
  picks a short burst of frames *around* the error (the movement into and out of
  it, not a single frozen still) — currently ~7 frames per correction. Each
  `KeyframeBurst` has a center timestamp, an ascending in-bounds list of frame
  timestamps, and the correction label. These same bursts are what the review
  and history views show moment by moment, and what round sync uploads as
  keyframe images.

## Orchestration

`RoundAnalyzer` (`services/round_analyzer.dart`) always runs pose + rules first
(metrics, review skeleton, base coaching — for free). Then, in an AI mode:

- **keyframe** — grabs the flagged-moment frames via `FrameGrabber` and sends
  them with the pose read as text;
- **full_frame** — grabs frames sampled across the whole round.

The model's coaching is attached to the `RoundAnalysis` as `modelCoaching`. If
there's no model configured, or the call throws, the AI modes fall back to the
rules-only analysis — verified by tests in `app/test/round_analyzer_test.dart`
and `app/test/ai/`.

## Roadmap note

Per the project's backend plan, full AI review is parked for a self-hosted Qwen
vision endpoint; because the client is OpenAI-compatible, bringing it online is a
config change plus flipping `AnalysisMode.fullFrame.available`.
