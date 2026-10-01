// Pure request parsing for the sparring review — validated and clamped here,
// so the server (not the app) decides frame rate, output budget and schema
// handling. Tested in request_test.ts.

import { isValidFileName } from "../analyze/video.ts";

/** Gemini rejects videoMetadata.fps above 24 (FIELD_INVALID). */
export const GEMINI_MAX_FPS = 24;

/**
 * A sparring report covers two fighters (up to 7 findings each), exchanges and
 * defence, after a thinking model has reasoned over a whole round — so it gets
 * a bigger output budget than the single-person review.
 */
export const MAX_OUTPUT_TOKENS = 16384;

export interface SparringGenerateRequest {
  fileName: string;
  fps: number;
  systemPrompt: string;
  userPrompt: string;
  maxTokens: number;
  temperature: number;
  responseSchema?: Record<string, unknown>;
}

export type Parsed =
  | { ok: true; value: SparringGenerateRequest }
  | { ok: false; message: string };

export function clampNumber(value: unknown, min: number, max: number, fallback: number) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.min(Math.max(n, min), max) : fallback;
}

/** Validates a /video/generate body; [maxFps] is the server's cost guard. */
export function parseGenerate(body: Record<string, unknown>, maxFps: number): Parsed {
  const fileName = body.fileName;
  if (!isValidFileName(fileName)) return { ok: false, message: "Missing or invalid fileName." };
  const userPrompt = String(body.userPrompt ?? "");
  if (!userPrompt) return { ok: false, message: "Missing userPrompt." };
  const wantsJson = body.responseMimeType === "application/json" &&
    body.responseSchema != null && typeof body.responseSchema === "object" &&
    !Array.isArray(body.responseSchema);
  return {
    ok: true,
    value: {
      fileName,
      fps: clampNumber(body.fps, 0.1, Math.min(maxFps, GEMINI_MAX_FPS), 1),
      systemPrompt: String(body.systemPrompt ?? ""),
      userPrompt,
      maxTokens: Math.round(clampNumber(body.maxTokens, 256, MAX_OUTPUT_TOKENS, 12000)),
      temperature: clampNumber(body.temperature, 0, 1, 0.2),
      responseSchema: wantsJson ? body.responseSchema as Record<string, unknown> : undefined,
    },
  };
}
