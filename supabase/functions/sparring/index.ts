// Sparring AI review proxy — sparring mode's own function, so the single-person
// `analyze` function is untouched. Same protocol as its Full AI review routes
// (the app's CoachVideoModel talks to both), same Gemini helpers (video.ts,
// imported read-only) and the SAME weekly AI allowance (consume_ai_quota /
// refund_ai_quota / ai_quota_remaining): one sparring round = one analysis.
//
// Routes (by path suffix under /functions/v1/sparring):
//  - /video/upload   — body { bytes, mimeType } → { uploadUrl }. Costs nothing,
//    refused when no allowance is left.
//  - /video/generate — body { fileName, fps, systemPrompt, userPrompt,
//    maxTokens?, temperature?, responseMimeType?, responseSchema? } →
//    { text, finishReason?, usage?, fps }. Spends one analysis; refunded on
//    any failure.
//
// Deploy: `supabase functions deploy sparring` (secrets shared with analyze:
// GEMINI_API_KEY / AI_API_KEY, AI_WEEKLY_LIMIT, optional AI_SPARRING_MODEL,
// AI_VIDEO_MAX_FPS, AI_VIDEO_MAX_BYTES, AI_VIDEO_MEDIA_RESOLUTION). See
// docs/SPARRING.md.

import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import {
  ALLOWED_VIDEO_MIME,
  deleteFile,
  GeminiError,
  generate,
  ownerTag,
  startUpload,
  waitUntilActive,
} from "../analyze/video.ts";
import { GEMINI_MAX_FPS, parseGenerate } from "./request.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const AI_API_KEY = Deno.env.get("AI_API_KEY") ?? "";
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? AI_API_KEY;
const WEEKLY_LIMIT = Number(Deno.env.get("AI_WEEKLY_LIMIT") ?? "3");
const MODEL = Deno.env.get("AI_SPARRING_MODEL") ??
  Deno.env.get("AI_VIDEO_MODEL") ?? Deno.env.get("AI_MODEL") ?? "gemini-2.5-flash";
const MAX_FPS = Math.min(
  Number(Deno.env.get("AI_VIDEO_MAX_FPS") ?? String(GEMINI_MAX_FPS)) || GEMINI_MAX_FPS,
  GEMINI_MAX_FPS,
);
// A 3-minute 1080p round is bigger than a portrait 720p shadow round.
const MAX_BYTES = Number(Deno.env.get("AI_VIDEO_MAX_BYTES") ?? String(800 * 1024 * 1024));
const MEDIA_RESOLUTION = Deno.env.get("AI_VIDEO_MEDIA_RESOLUTION") ?? "";

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
    `You've used all ${WEEKLY_LIMIT} AI analyses for this week. Your allowance resets Monday.`,
    "ai_quota_exceeded",
  );

Deno.serve(async (req) => {
  if (req.method !== "POST") return error(405, "Method not allowed.");
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return error(401, "Missing bearer token.");
  }
  if (!GEMINI_API_KEY) return error(503, "AI sparring review isn't configured.");

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const uid = await userId(supabase, authHeader);
  if (!uid) return error(401, "Could not verify your account.");

  const path = new URL(req.url).pathname.replace(/\/+$/, "");
  if (path.endsWith("/video/upload")) return upload(req, supabase, uid);
  if (path.endsWith("/video/generate")) return review(req, supabase, uid);
  return error(404, "Unknown route.");
});

async function userId(supabase: SupabaseClient, authHeader: string) {
  const token = authHeader.slice("bearer ".length).trim();
  const { data, error: authError } = await supabase.auth.getUser(token);
  return authError ? null : data.user?.id ?? null;
}

async function upload(req: Request, supabase: SupabaseClient, uid: string) {
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
  if (bytes > MAX_BYTES) return error(413, "That round's video is too large to review.");
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

async function review(req: Request, supabase: SupabaseClient, uid: string) {
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return error(400, "Invalid JSON body.");
  }
  const parsed = parseGenerate(body, MAX_FPS);
  if (!parsed.ok) return error(400, parsed.message);
  const input = parsed.value;

  // Reserve one analysis from the shared weekly allowance before spending.
  const { data: remaining, error: quotaError } = await supabase.rpc("consume_ai_quota", {
    p_weekly_limit: WEEKLY_LIMIT,
  });
  if (quotaError) {
    await deleteFile(GEMINI_API_KEY, input.fileName);
    const exceeded = (quotaError.message ?? "").includes("weekly AI limit") ||
      (quotaError.details ?? "").includes("ai_quota_exceeded");
    return exceeded ? quotaExceeded() : error(401, "Could not verify your account.");
  }
  const refund = () => supabase.rpc("refund_ai_quota");

  try {
    const file = await waitUntilActive(GEMINI_API_KEY, input.fileName, { timeoutMs: 60_000 });
    if (file.displayName !== ownerTag(uid)) {
      await refund();
      return error(403, "That upload belongs to another account.");
    }
    const result = await generate(GEMINI_API_KEY, MODEL, {
      file,
      fps: input.fps,
      systemPrompt: input.systemPrompt,
      userPrompt: input.userPrompt,
      maxTokens: input.maxTokens,
      temperature: input.temperature,
      mediaResolution: MEDIA_RESOLUTION || undefined,
      responseSchema: input.responseSchema,
    });
    await deleteFile(GEMINI_API_KEY, input.fileName);
    return json(200, { ...result, fps: input.fps }, {
      "X-AI-Remaining": String(remaining ?? 0),
    });
  } catch (e) {
    await refund();
    // Still processing: keep the upload so the app's retry can reuse it.
    if (!(e instanceof GeminiError && e.status === 503)) {
      await deleteFile(GEMINI_API_KEY, input.fileName);
    }
    return geminiError(e);
  }
}

function geminiError(e: unknown) {
  if (e instanceof GeminiError) return error(e.status, e.message);
  return error(502, `Could not reach the model: ${e}`);
}
