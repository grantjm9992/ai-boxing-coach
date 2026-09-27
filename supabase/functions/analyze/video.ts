// Gemini-native video calls for "Full AI review".
//
// The OpenAI-compatible endpoint the chat route uses can't set a per-video
// frame rate, so the full-round path talks to the native Gemini API instead:
//
//   1. startUpload()   — opens a resumable Files API upload with the server key
//                        and returns Google's upload URL. That URL is
//                        self-authorising, so the phone streams the video
//                        straight to Google: no key on the device, and no
//                        100+ MB body relayed through this function.
//   2. waitUntilActive() — video files are processed after upload; generation
//                        only works once the file is ACTIVE.
//   3. generate()      — generateContent with the file + `videoMetadata.fps`.
//   4. deleteFile()    — best-effort cleanup (Google would drop it after 48 h
//                        anyway, but a boxer's training video shouldn't linger).
//
// Pure HTTP helpers only — auth, quota and routing live in index.ts.

export const GEMINI_API_BASE = "https://generativelanguage.googleapis.com";

/** Accepted upload types — what the phone recorders produce. */
export const ALLOWED_VIDEO_MIME = new Set(["video/mp4", "video/quicktime"]);

/** File names the Files API hands out: `files/<id>`. */
const FILE_NAME = /^files\/[a-z0-9-]{1,64}$/;

export class GeminiError extends Error {
  constructor(message: string, readonly status = 502) {
    super(message);
  }
}

export interface GeminiFile {
  name: string;
  uri: string;
  mimeType: string;
  state: string;
  displayName?: string;
}

export interface VideoGenerateInput {
  file: GeminiFile;
  fps: number;
  systemPrompt: string;
  userPrompt: string;
  maxTokens: number;
  temperature: number;
  mediaResolution?: string;
}

export interface VideoGenerateResult {
  text: string;
  finishReason?: string;
  usage?: unknown;
}

export const isValidFileName = (name: unknown): name is string =>
  typeof name === "string" && FILE_NAME.test(name);

/** The display name that ties an upload to the user who started it. */
export const ownerTag = (userId: string) => `aicornerman:${userId}`;

export async function startUpload(
  apiKey: string,
  bytes: number,
  mimeType: string,
  displayName: string,
): Promise<string> {
  const res = await fetch(`${GEMINI_API_BASE}/upload/v1beta/files`, {
    method: "POST",
    headers: {
      "x-goog-api-key": apiKey,
      "X-Goog-Upload-Protocol": "resumable",
      "X-Goog-Upload-Command": "start",
      "X-Goog-Upload-Header-Content-Length": String(bytes),
      "X-Goog-Upload-Header-Content-Type": mimeType,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ file: { display_name: displayName } }),
  });
  const uploadUrl = res.headers.get("x-goog-upload-url");
  if (!res.ok || !uploadUrl) {
    throw new GeminiError(
      `Could not start the video upload (${res.status}): ${await brief(res)}`,
    );
  }
  return uploadUrl;
}

export async function getFile(apiKey: string, name: string): Promise<GeminiFile> {
  const res = await fetch(`${GEMINI_API_BASE}/v1beta/${name}`, {
    headers: { "x-goog-api-key": apiKey },
  });
  if (res.status === 404) throw new GeminiError("Video upload not found.", 404);
  if (!res.ok) {
    throw new GeminiError(`Could not read the upload (${res.status}): ${await brief(res)}`);
  }
  const body = await res.json();
  return {
    name: body.name,
    uri: body.uri,
    mimeType: body.mimeType,
    state: body.state,
    displayName: body.displayName,
  };
}

/**
 * Polls until Google has finished processing the video. Throws on FAILED, or
 * once [timeoutMs] passes — the caller refunds the quota either way.
 */
export async function waitUntilActive(
  apiKey: string,
  name: string,
  { timeoutMs = 120_000, intervalMs = 2_000 } = {},
): Promise<GeminiFile> {
  const deadline = Date.now() + timeoutMs;
  while (true) {
    const file = await getFile(apiKey, name);
    if (file.state === "ACTIVE") return file;
    if (file.state === "FAILED") {
      throw new GeminiError("Google could not process the video.");
    }
    if (Date.now() + intervalMs > deadline) {
      throw new GeminiError("The video is still processing — try again shortly.", 503);
    }
    await new Promise((r) => setTimeout(r, intervalMs));
  }
}

/** The generateContent body. Exported so the wire shape is easy to inspect. */
export function buildGenerateBody(input: VideoGenerateInput) {
  return {
    system_instruction: { parts: [{ text: input.systemPrompt }] },
    contents: [
      {
        role: "user",
        parts: [
          {
            file_data: { mime_type: input.file.mimeType, file_uri: input.file.uri },
            video_metadata: { fps: input.fps },
          },
          { text: input.userPrompt },
        ],
      },
    ],
    generationConfig: {
      maxOutputTokens: input.maxTokens,
      temperature: input.temperature,
      ...(input.mediaResolution ? { mediaResolution: input.mediaResolution } : {}),
    },
  };
}

export async function generate(
  apiKey: string,
  model: string,
  input: VideoGenerateInput,
): Promise<VideoGenerateResult> {
  const res = await fetch(
    `${GEMINI_API_BASE}/v1beta/models/${encodeURIComponent(model)}:generateContent`,
    {
      method: "POST",
      headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
      body: JSON.stringify(buildGenerateBody(input)),
    },
  );
  if (!res.ok) {
    throw new GeminiError(`Model returned ${res.status}: ${await brief(res)}`, res.status);
  }
  const body = await res.json();
  const candidate = body?.candidates?.[0];
  const text = ((candidate?.content?.parts ?? []) as Array<{ text?: string; thought?: boolean }>)
    .filter((p) => typeof p.text === "string" && !p.thought)
    .map((p) => p.text)
    .join("")
    .trim();
  if (!text) {
    // Usually a thinking model spending the whole output budget on reasoning
    // (finishReason MAX_TOKENS) — surfaced so it's diagnosable.
    throw new GeminiError(
      `No text in model response (finishReason: ${candidate?.finishReason ?? "none"}).`,
    );
  }
  return { text, finishReason: candidate?.finishReason, usage: body?.usageMetadata };
}

export async function deleteFile(apiKey: string, name: string): Promise<void> {
  try {
    await fetch(`${GEMINI_API_BASE}/v1beta/${name}`, {
      method: "DELETE",
      headers: { "x-goog-api-key": apiKey },
    });
  } catch (_) {
    // Best effort — Google expires files after 48 h regardless.
  }
}

async function brief(res: Response): Promise<string> {
  const text = await res.text().catch(() => "");
  return text.length > 200 ? `${text.slice(0, 200)}…` : text;
}
