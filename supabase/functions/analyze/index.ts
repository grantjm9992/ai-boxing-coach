// AI coaching proxy — the app calls THIS, never the model provider directly.
//
// Why it exists:
//  - The provider API key stays server-side (a Supabase secret). Shipping it in
//    the APK would let anyone extract it and drain the billing.
//  - It enforces the weekly AI cap in SQL, which the device can't be trusted
//    to do.
//
// Routes (by path suffix under /functions/v1/analyze):
//  - /chat/completions — OpenAI chat-completions in, provider response passed
//    straight back out, so the Flutter `OpenAiCompatibleVisionModel` talks to it
//    unchanged. Used by "Pose + AI on key moments". (Also the fallback for any
//    other path, so older app builds keep working.)
//  - /video/upload     — "Full AI review", step 1: hands the phone a Google
//    resumable-upload URL so the round video goes straight to Gemini.
//  - /video/generate   — step 2: runs Gemini natively over the uploaded video at
//    the requested frame rate and returns the coaching text.
//
// Deploy + secrets: see docs/AI_PROXY.md.

import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import {
  ALLOWED_VIDEO_MIME,
  deleteFile,
  GeminiError,
  generate,
  isValidFileName,
  ownerTag,
  startUpload,
  waitUntilActive,
} from "./video.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

// The real model, configured server-side. Defaults to Gemini's OpenAI-compatible
// endpoint; swap for a self-hosted vLLM (Qwen) later without touching the app.
const AI_BASE_URL = (Deno.env.get("AI_BASE_URL") ??
  "https://generativelanguage.googleapis.com/v1beta/openai").replace(/\/+$/, "");
const AI_API_KEY = Deno.env.get("AI_API_KEY") ?? "";
const AI_MODEL = Deno.env.get("AI_MODEL") ?? "gemini-2.5-flash";
const WEEKLY_LIMIT = Number(Deno.env.get("AI_WEEKLY_LIMIT") ?? "3");

// Full AI review always goes to Gemini natively (the only provider here that
// takes a whole video with a frame rate). Its key defaults to AI_API_KEY.
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? AI_API_KEY;
const AI_VIDEO_MODEL = Deno.env.get("AI_VIDEO_MODEL") ?? AI_MODEL;
// Gemini rejects videoMetadata.fps above 24 (FIELD_INVALID).
const GEMINI_MAX_FPS = 24;
// Cost guards: the server, not the app, has the final say.
const AI_VIDEO_MAX_FPS = Math.min(
  Number(Deno.env.get("AI_VIDEO_MAX_FPS") ?? String(GEMINI_MAX_FPS)) || GEMINI_MAX_FPS,
  GEMINI_MAX_FPS,
);
const AI_VIDEO_MAX_BYTES = Number(
  Deno.env.get("AI_VIDEO_MAX_BYTES") ?? String(500 * 1024 * 1024),
);
// Optional, e.g. MEDIA_RESOLUTION_LOW (~66 tokens/frame instead of ~258).
const AI_VIDEO_MEDIA_RESOLUTION = Deno.env.get("AI_VIDEO_MEDIA_RESOLUTION") ?? "";

const json = (status: number, body: unknown, headers: HeadersInit = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });

const error = (status: number, message: string, code?: string) =>
  json(status, { error: code ? { code, message } : { message } });

const quotaExceeded = () =>
  error(
    429,
    `You've used all ${WEEKLY_LIMIT} AI analyses for this week. ` +
      `Your allowance resets Monday.`,
    "ai_quota_exceeded",
  );

Deno.serve(async (req) => {
  if (req.method !== "POST") return error(405, "Method not allowed.");

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return error(401, "Missing bearer token.");
  }

  // A client scoped to the caller's token, so the quota functions see their
  // auth.uid() and RLS applies. (verify_jwt on the function already rejected
  // unauthenticated callers at the gateway.)
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const path = new URL(req.url).pathname.replace(/\/+$/, "");
  if (path.endsWith("/video/upload")) return handleVideoUpload(req, supabase, authHeader);
  if (path.endsWith("/video/generate")) {
    return handleVideoGenerate(req, supabase, authHeader);
  }
  return handleChat(req, supabase);
});

// ---------------------------------------------------------------------------
// Quota helpers — reserve before spending on the model, refund on any failure,
// so a failed call never costs the user one of their weekly analyses.
// ---------------------------------------------------------------------------

type Reservation = { ok: true; remaining: number } | { ok: false; response: Response };

async function reserveQuota(supabase: SupabaseClient): Promise<Reservation> {
  const { data, error: quotaError } = await supabase.rpc("consume_ai_quota", {
    p_weekly_limit: WEEKLY_LIMIT,
  });
  if (!quotaError) return { ok: true, remaining: data ?? 0 };
  const exceeded = (quotaError.message ?? "").includes("weekly AI limit") ||
    (quotaError.details ?? "").includes("ai_quota_exceeded");
  return {
    ok: false,
    response: exceeded ? quotaExceeded() : error(401, "Could not verify your account."),
  };
}

const refundQuota = (supabase: SupabaseClient) => supabase.rpc("refund_ai_quota");

async function userId(supabase: SupabaseClient, authHeader: string) {
  const token = authHeader.slice("bearer ".length).trim();
  const { data, error: authError } = await supabase.auth.getUser(token);
  return authError ? null : data.user?.id ?? null;
}

// ---------------------------------------------------------------------------
// /chat/completions — key moments (unchanged behaviour).
// ---------------------------------------------------------------------------

async function handleChat(req: Request, supabase: SupabaseClient) {
  const reservation = await reserveQuota(supabase);
  if (!reservation.ok) return reservation.response;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    await refundQuota(supabase);
    return error(400, "Invalid JSON body.");
  }

  // The server dictates the model — never let the client pick a pricier one.
  body.model = AI_MODEL;

  let providerRes: Response;
  try {
    providerRes = await fetch(`${AI_BASE_URL}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${AI_API_KEY}`,
      },
      body: JSON.stringify(body),
    });
  } catch (e) {
    await refundQuota(supabase);
    return error(502, `Could not reach the model: ${e}`);
  }

  const text = await providerRes.text();
  if (!providerRes.ok) {
    await refundQuota(supabase);
    return new Response(text, {
      status: providerRes.status,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Success: pass the provider's response straight through, plus a header the
  // app can surface ("2 left this week"). Body shape is unchanged for the client.
  return new Response(text, {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "X-AI-Remaining": String(reservation.remaining),
    },
  });
}

// ---------------------------------------------------------------------------
// /video/upload — body: { bytes: number, mimeType: string }
// Returns { uploadUrl }. Costs no quota, but is refused when none is left so a
// user can't upload a round that could never be analysed.
// ---------------------------------------------------------------------------

async function handleVideoUpload(
  req: Request,
  supabase: SupabaseClient,
  authHeader: string,
) {
  if (!GEMINI_API_KEY) return error(503, "Full AI review isn't configured.");

  const uid = await userId(supabase, authHeader);
  if (!uid) return error(401, "Could not verify your account.");

  let bytes: number;
  let mimeType: string;
  try {
    const body = await req.json();
    bytes = Number(body.bytes);
    mimeType = String(body.mimeType ?? "");
  } catch {
    return error(400, "Invalid JSON body.");
  }
  if (!Number.isFinite(bytes) || bytes <= 0) return error(400, "Missing video size.");
  if (bytes > AI_VIDEO_MAX_BYTES) return error(413, "That round's video is too large to review.");
  if (!ALLOWED_VIDEO_MIME.has(mimeType)) return error(415, `Unsupported video type: ${mimeType}`);

  const { data: remaining } = await supabase.rpc("ai_quota_remaining", {
    p_weekly_limit: WEEKLY_LIMIT,
  });
  if (typeof remaining === "number" && remaining <= 0) return quotaExceeded();

  try {
    const uploadUrl = await startUpload(GEMINI_API_KEY, bytes, mimeType, ownerTag(uid));
    return json(200, { uploadUrl });
  } catch (e) {
    return geminiError(e);
  }
}

// ---------------------------------------------------------------------------
// /video/generate — body: { fileName, fps, systemPrompt, userPrompt,
// maxTokens?, temperature? }. Returns { text, finishReason?, usage? }.
// ---------------------------------------------------------------------------

async function handleVideoGenerate(
  req: Request,
  supabase: SupabaseClient,
  authHeader: string,
) {
  if (!GEMINI_API_KEY) return error(503, "Full AI review isn't configured.");

  const uid = await userId(supabase, authHeader);
  if (!uid) return error(401, "Could not verify your account.");

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return error(400, "Invalid JSON body.");
  }
  const fileName = body.fileName;
  if (!isValidFileName(fileName)) return error(400, "Missing or invalid fileName.");
  const systemPrompt = String(body.systemPrompt ?? "");
  const userPrompt = String(body.userPrompt ?? "");
  if (!userPrompt) return error(400, "Missing userPrompt.");
  const requestedFps = Number(body.fps ?? 1);
  const fps = Math.min(
    Math.max(Number.isFinite(requestedFps) ? requestedFps : 1, 0.1),
    AI_VIDEO_MAX_FPS,
  );
  const maxTokens = clampInt(body.maxTokens, 256, 8192, 2048);
  const temperature = clampNumber(body.temperature, 0, 1, 0.4);

  const reservation = await reserveQuota(supabase);
  if (!reservation.ok) {
    await deleteFile(GEMINI_API_KEY, fileName);
    return reservation.response;
  }

  try {
    // Bounded well inside the Edge Function's request limit: a long video may
    // still be processing, in which case we answer 503 (upload kept, quota
    // refunded) and the app simply calls generate again.
    const file = await waitUntilActive(GEMINI_API_KEY, fileName, { timeoutMs: 60_000 });
    // Only the user who started the upload may analyse it.
    if (file.displayName !== ownerTag(uid)) {
      await refundQuota(supabase);
      return error(403, "That upload belongs to another account.");
    }
    const result = await generate(GEMINI_API_KEY, AI_VIDEO_MODEL, {
      file,
      fps,
      systemPrompt,
      userPrompt,
      maxTokens,
      temperature,
      mediaResolution: AI_VIDEO_MEDIA_RESOLUTION || undefined,
    });
    await deleteFile(GEMINI_API_KEY, fileName);
    return json(200, { ...result, fps }, { "X-AI-Remaining": String(reservation.remaining) });
  } catch (e) {
    await refundQuota(supabase);
    // Keep the upload if it's only still processing, so a retry can reuse it.
    if (!(e instanceof GeminiError && e.status === 503)) {
      await deleteFile(GEMINI_API_KEY, fileName);
    }
    return geminiError(e);
  }
}

function geminiError(e: unknown) {
  if (e instanceof GeminiError) return error(e.status, e.message);
  return error(502, `Could not reach the model: ${e}`);
}

function clampNumber(value: unknown, min: number, max: number, fallback: number) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.min(Math.max(n, min), max) : fallback;
}

function clampInt(value: unknown, min: number, max: number, fallback: number) {
  return Math.round(clampNumber(value, min, max, fallback));
}
