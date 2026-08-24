// AI coaching proxy — the app calls THIS, never the model provider directly.
//
// Why it exists:
//  - The provider API key stays server-side (a Supabase secret). Shipping it in
//    the APK would let anyone extract it and drain the billing.
//  - It enforces the free-tier weekly cap (3 analyses / user / week) in SQL,
//    which the device can't be trusted to do.
//
// Wire shape: OpenAI chat-completions in, provider response passed straight
// back out, so the Flutter `OpenAiCompatibleVisionModel` talks to it unchanged —
// only its base URL points here and its bearer is the user's Supabase token.
//
// Deploy + secrets: see docs/AI_PROXY.md.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

// The real model, configured server-side. Defaults to Gemini's OpenAI-compatible
// endpoint; swap for a self-hosted vLLM (Qwen) later without touching the app.
const AI_BASE_URL = (Deno.env.get("AI_BASE_URL") ??
  "https://generativelanguage.googleapis.com/v1beta/openai").replace(/\/+$/, "");
const AI_API_KEY = Deno.env.get("AI_API_KEY") ?? "";
const AI_MODEL = Deno.env.get("AI_MODEL") ?? "gemini-2.5-flash";
const WEEKLY_LIMIT = Number(Deno.env.get("AI_WEEKLY_LIMIT") ?? "3");

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: { message: "Method not allowed." } });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json(401, { error: { message: "Missing bearer token." } });
  }

  // A client scoped to the caller's token, so consume_ai_quota() sees their
  // auth.uid() and RLS applies. (verify_jwt on the function already rejected
  // unauthenticated callers at the gateway.)
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  // --- Reserve one unit of the weekly quota before spending on the model. ---
  const { data: remaining, error: quotaError } = await supabase.rpc(
    "consume_ai_quota",
    { p_weekly_limit: WEEKLY_LIMIT },
  );
  if (quotaError) {
    const exceeded = (quotaError.message ?? "").includes("weekly AI limit") ||
      (quotaError.details ?? "").includes("ai_quota_exceeded");
    if (exceeded) {
      return json(429, {
        error: {
          code: "ai_quota_exceeded",
          message:
            `You've used all ${WEEKLY_LIMIT} AI analyses for this week. ` +
            `Your allowance resets Monday.`,
        },
      });
    }
    return json(401, { error: { message: "Could not verify your account." } });
  }

  // --- Forward to the real model. On any failure, refund the reserved unit. ---
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    await supabase.rpc("refund_ai_quota");
    return json(400, { error: { message: "Invalid JSON body." } });
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
    await supabase.rpc("refund_ai_quota");
    return json(502, {
      error: { message: `Could not reach the model: ${e}` },
    });
  }

  const text = await providerRes.text();
  if (!providerRes.ok) {
    await supabase.rpc("refund_ai_quota");
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
      "X-AI-Remaining": String(remaining ?? ""),
    },
  });
});
