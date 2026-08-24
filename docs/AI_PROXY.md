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

## How the app targets it
`OpenAiCompatibleVisionModel` appends `/chat/completions` to its base URL, so the
app points at:
```
<SUPABASE_URL>/functions/v1/analyze
```
with the user's `session.accessToken` as the bearer. See
`app/lib/services/ai/coach_vision_model.dart`.

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
