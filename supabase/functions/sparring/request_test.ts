import assert from "node:assert/strict";

import { GEMINI_MAX_FPS, MAX_OUTPUT_TOKENS, parseGenerate } from "./request.ts";

const base = { fileName: "files/abc123", userPrompt: "Review the round." };

Deno.test("clamps fps to Gemini's maximum and the server's guard", () => {
  const high = parseGenerate({ ...base, fps: 60 }, 24);
  assert.ok(high.ok);
  assert.equal(high.ok && high.value.fps, GEMINI_MAX_FPS);
  const guarded = parseGenerate({ ...base, fps: 24 }, 10);
  assert.equal(guarded.ok && guarded.value.fps, 10);
});

Deno.test("gives the two-fighter report a bigger, bounded output budget", () => {
  const def = parseGenerate(base, 24);
  assert.equal(def.ok && def.value.maxTokens, 12000);
  const big = parseGenerate({ ...base, maxTokens: 99999 }, 24);
  assert.equal(big.ok && big.value.maxTokens, MAX_OUTPUT_TOKENS);
});

Deno.test("passes a JSON schema through only with the JSON mime type", () => {
  const schema = { type: "OBJECT" };
  const withMime = parseGenerate(
    { ...base, responseMimeType: "application/json", responseSchema: schema },
    24,
  );
  assert.deepEqual(withMime.ok && withMime.value.responseSchema, schema);
  const without = parseGenerate({ ...base, responseSchema: schema }, 24);
  assert.equal(without.ok && without.value.responseSchema, undefined);
});

Deno.test("rejects a bad file name or a missing prompt", () => {
  assert.equal(parseGenerate({ ...base, fileName: "../etc" }, 24).ok, false);
  assert.equal(parseGenerate({ fileName: "files/x" }, 24).ok, false);
});
