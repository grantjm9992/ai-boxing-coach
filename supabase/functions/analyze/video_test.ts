// Unit tests for the Gemini video helpers — fetch is stubbed, no network.
// Run: deno test supabase/functions/analyze/video_test.ts

import nodeAssert from "node:assert/strict";
import {
  buildGenerateBody,
  GeminiError,
  generate,
  isValidFileName,
  ownerTag,
  startUpload,
  waitUntilActive,
} from "./video.ts";

const assert = (v: unknown) => nodeAssert.ok(v);
const assertEquals = (a: unknown, b: unknown) => nodeAssert.deepStrictEqual(a, b);
async function assertRejects<E extends Error>(
  fn: () => Promise<unknown>,
  type: new (...args: never[]) => E,
): Promise<E> {
  try {
    await fn();
  } catch (e) {
    nodeAssert.ok(e instanceof type, `expected ${type.name}, got ${e}`);
    return e as E;
  }
  throw new Error("expected a rejection");
}

type Handler = (url: string, init?: RequestInit) => Response;

function stubFetch(handler: Handler) {
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  const original = globalThis.fetch;
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input.toString();
    calls.push({ url, init });
    return Promise.resolve(handler(url, init));
  }) as typeof fetch;
  return { calls, restore: () => (globalThis.fetch = original) };
}

const file = {
  name: "files/abc123",
  uri: "https://generativelanguage.googleapis.com/v1beta/files/abc123",
  mimeType: "video/mp4",
  state: "ACTIVE",
  displayName: ownerTag("user-1"),
};

Deno.test("buildGenerateBody sends the video with its fps and the prompts", () => {
  const body = buildGenerateBody({
    file,
    fps: 30,
    systemPrompt: "sys",
    userPrompt: "watch this",
    maxTokens: 2048,
    temperature: 0.4,
  });
  const parts = body.contents[0].parts;
  assertEquals(parts[0], {
    file_data: { mime_type: "video/mp4", file_uri: file.uri },
    video_metadata: { fps: 30 },
  });
  assertEquals(parts[1], { text: "watch this" });
  assertEquals(body.system_instruction.parts[0].text, "sys");
  assertEquals(body.generationConfig.maxOutputTokens, 2048);
  assert(!("mediaResolution" in body.generationConfig));
});

Deno.test("buildGenerateBody passes a media resolution when set", () => {
  const body = buildGenerateBody({
    file,
    fps: 30,
    systemPrompt: "",
    userPrompt: "x",
    maxTokens: 1024,
    temperature: 0.4,
    mediaResolution: "MEDIA_RESOLUTION_LOW",
  });
  assertEquals(
    (body.generationConfig as Record<string, unknown>).mediaResolution,
    "MEDIA_RESOLUTION_LOW",
  );
});

Deno.test("startUpload returns Google's upload URL", async () => {
  const stub = stubFetch(() =>
    new Response("{}", { headers: { "x-goog-upload-url": "https://upload/xyz" } })
  );
  try {
    const url = await startUpload("key", 1234, "video/mp4", ownerTag("u"));
    assertEquals(url, "https://upload/xyz");
    const headers = stub.calls[0].init?.headers as Record<string, string>;
    assertEquals(headers["X-Goog-Upload-Header-Content-Length"], "1234");
    assertEquals(headers["X-Goog-Upload-Command"], "start");
  } finally {
    stub.restore();
  }
});

Deno.test("startUpload fails loudly without an upload URL", async () => {
  const stub = stubFetch(() => new Response("nope", { status: 400 }));
  try {
    await assertRejects(
      () => startUpload("key", 1, "video/mp4", "d"),
      GeminiError,
    );
  } finally {
    stub.restore();
  }
});

Deno.test("waitUntilActive polls through PROCESSING", async () => {
  let n = 0;
  const stub = stubFetch(() =>
    Response.json({ ...file, state: n++ < 2 ? "PROCESSING" : "ACTIVE" })
  );
  try {
    const f = await waitUntilActive("key", file.name, { intervalMs: 1 });
    assertEquals(f.state, "ACTIVE");
    assertEquals(stub.calls.length, 3);
  } finally {
    stub.restore();
  }
});

Deno.test("waitUntilActive gives up with 503 while still processing", async () => {
  const stub = stubFetch(() => Response.json({ ...file, state: "PROCESSING" }));
  try {
    const err = await assertRejects(
      () => waitUntilActive("key", file.name, { timeoutMs: 5, intervalMs: 10 }),
      GeminiError,
    );
    assertEquals(err.status, 503);
  } finally {
    stub.restore();
  }
});

Deno.test("generate joins the text parts and skips thoughts", async () => {
  const stub = stubFetch(() =>
    Response.json({
      candidates: [{
        finishReason: "STOP",
        content: { parts: [{ text: "thinking…", thought: true }, { text: "Hands up " }, { text: "after the cross." }] },
      }],
      usageMetadata: { promptTokenCount: 10 },
    })
  );
  try {
    const result = await generate("key", "gemini-2.5-flash", {
      file,
      fps: 30,
      systemPrompt: "s",
      userPrompt: "u",
      maxTokens: 1024,
      temperature: 0.4,
    });
    assertEquals(result.text, "Hands up after the cross.");
    assert(stub.calls[0].url.endsWith("/models/gemini-2.5-flash:generateContent"));
  } finally {
    stub.restore();
  }
});

Deno.test("generate surfaces an empty response with its finish reason", async () => {
  const stub = stubFetch(() =>
    Response.json({ candidates: [{ finishReason: "MAX_TOKENS", content: { parts: [] } }] })
  );
  try {
    const err = await assertRejects(
      () =>
        generate("key", "m", {
          file,
          fps: 30,
          systemPrompt: "",
          userPrompt: "u",
          maxTokens: 256,
          temperature: 0,
        }),
      GeminiError,
    );
    assert(err.message.includes("MAX_TOKENS"));
  } finally {
    stub.restore();
  }
});

Deno.test("isValidFileName only accepts Files API names", () => {
  assert(isValidFileName("files/abc-123"));
  assert(!isValidFileName("files/../secrets"));
  assert(!isValidFileName("models/gemini"));
  assert(!isValidFileName(42));
});
