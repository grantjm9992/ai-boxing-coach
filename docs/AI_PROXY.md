# AI coaching proxy (Supabase Edge Function)

The app must **not** ship a model API key — anything in the APK is extractable.
Instead the app calls the `analyze` edge function with the signed-in user's
Supabase token; the function holds the real key server-side and enforces the
free-tier weekly cap (3 analyses / user / week).

- Function: `supabase/functions/analyze/index.ts`
- Quota (SQL): `supabase/migrations/0003_ai_usage.sql`
  (`ai_usage` table + `consume_ai_quota` / `refund_ai_quota` / `ai_quota_remaining`)

## One-time setup

### 1. Run the migration
Apply `0003_ai_usage.sql` in the Supabase dashboard (SQL editor) or via
`supabase db push`.

### 2. Set the model secrets
```bash
supabase secrets set \
  AI_API_KEY="<your Gemini or Qwen key>" \
  AI_MODEL="gemini-2.5-flash" \
  AI_BASE_URL="https://generativelanguage.googleapis.com/v1beta/openai" \
  AI_WEEKLY_LIMIT="3"
```
`SUPABASE_URL` and `SUPABASE_ANON_KEY` are injected by the platform — don't set
them. To move to a self-hosted Qwen (vLLM) later, only change `AI_BASE_URL` +
`AI_MODEL`; nothing in the app changes.

### 3. Deploy
```bash
supabase functions deploy analyze
```
Leave JWT verification **on** (the default) so only signed-in users can call it.

### 4. Full AI review (video) — optional secrets
Full AI review calls the **native** Gemini API (the OpenAI-compatible endpoint
can't set a per-video frame rate), so it needs a Gemini key even if `AI_BASE_URL`
points elsewhere:
```bash
supabase secrets set \
  GEMINI_API_KEY="<Gemini key>" \
  AI_VIDEO_MODEL="gemini-2.5-flash" \
  AI_VIDEO_MAX_FPS="24" \
  AI_VIDEO_MAX_BYTES="524288000" \
  AI_VIDEO_MEDIA_RESOLUTION="MEDIA_RESOLUTION_LOW"
```
- `GEMINI_API_KEY` defaults to `AI_API_KEY`; `AI_VIDEO_MODEL` to `AI_MODEL`.
- `AI_VIDEO_MAX_FPS` is the server-side cap on the fps the app asks for
  (default and maximum 24 — Gemini rejects anything higher).
- `AI_VIDEO_MAX_BYTES` caps the upload (default 500 MB).
- `AI_VIDEO_MEDIA_RESOLUTION` is optional. Unset uses Gemini's default, which
  for video on current models **is** the low setting (~66–70 tokens/frame);
  `MEDIA_RESOLUTION_HIGH` is ~258–280 tokens/frame for finer detail at about
  4× the cost.

Redeploy after changing code: `supabase functions deploy analyze`.

## How the app targets it
`OpenAiCompatibleVisionModel` appends `/chat/completions` to its base URL, so the
app points at:
```
<SUPABASE_URL>/functions/v1/analyze
```
with the user's `session.accessToken` as the bearer. See
`app/lib/services/ai/coach_vision_model.dart`.

## Full AI review flow (`/video/*`)
The round video (often 100+ MB) never passes through the function:

1. `POST …/analyze/video/upload` `{bytes, mimeType}` — checks the user has
   allowance left, opens a Gemini Files API resumable upload tagged with the
   user's id, and returns `{uploadUrl}`. Costs no quota.
2. The app streams the file to `uploadUrl` (self-authorising — no key on the
   device) and gets back `{file: {name: "files/…"}}`.
3. `POST …/analyze/video/generate` `{fileName, fps, systemPrompt, userPrompt,
   maxTokens?, temperature?}` — reserves one analysis, waits for the file to be
   `ACTIVE`, checks it belongs to the caller, runs `generateContent` with
   `videoMetadata.fps` (clamped to `AI_VIDEO_MAX_FPS`), deletes the upload and
   returns `{text, finishReason, usage, fps}`. Any failure refunds the analysis.
   When the body carries `responseMimeType: "application/json"` and a
   `responseSchema`, both go into `generationConfig`, so Gemini must answer
   with JSON of that shape (Full AI review's findings report).

App side: `CoachVideoModel` (`app/lib/services/ai/coach_video_model.dart`).
Unit tests for the Gemini helpers: `deno test supabase/functions/analyze/video_test.ts`.

**Cost:** one Full AI review is one weekly analysis, but costs far more tokens
than a key-moment one — roughly frames × tokens-per-frame (≈66–70 at the
default, low, video resolution; ≈258–280 at high). A 3-minute round at 24 fps
is ~4,300 frames: ≈0.3 M tokens at the default, ≈1.1 M at high — the latter is
past a 1 M-token context, so keep high resolution for short clips only.

## Behaviour
- **Reserve → call model → refund on failure**, so a failed/timed-out model call
  never costs the user one of their weekly analyses.
- Over the cap → HTTP **429** with `code: "ai_quota_exceeded"` and a message the
  app shows; the allowance resets Monday (UTC).
- Success responses carry `X-AI-Remaining: <n>` for a "N left this week" hint.

## Quick test
```bash
TOKEN="<a signed-in user's access token>"
curl -sS -X POST \
  "$SUPABASE_URL/functions/v1/analyze/chat/completions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say hi in 3 words."}]}'
```
Call it four times with the same user to see the 4th return 429.
