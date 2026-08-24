// Account + data deletion — Google Play requires an in-app way to delete the
// account and its data (and a matching web request path). Deleting an auth user
// needs the service role, which can't ship in the app, so it runs here.
//
// The signed-in user calls this with their own token; we delete their Storage
// objects (keyframes/pose/clips, first path segment = their uid) and then the
// auth user, which cascades every DB row (profiles/sessions/rounds/analyses/
// keyframes all `on delete cascade references auth.users`).
//
// Deploy: `supabase functions deploy delete-account`. Uses SUPABASE_URL,
// SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY (all platform-injected).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const BUCKETS = ["keyframes", "pose", "clips"];

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// Storage.list isn't recursive; walk the tree under a prefix and collect files.
async function listAllFiles(
  admin: ReturnType<typeof createClient>,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const files: string[] = [];
  const { data, error } = await admin.storage.from(bucket).list(prefix, {
    limit: 1000,
  });
  if (error || !data) return files;
  for (const entry of data) {
    const path = prefix ? `${prefix}/${entry.name}` : entry.name;
    // Folders come back with a null id; files have metadata.
    if (entry.id === null) {
      files.push(...await listAllFiles(admin, bucket, path));
    } else {
      files.push(path);
    }
  }
  return files;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: { message: "Method not allowed." } });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json(401, { error: { message: "Missing bearer token." } });
  }

  // Who's asking (scoped to their token).
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  const uid = userData?.user?.id;
  if (userErr || !uid) {
    return json(401, { error: { message: "Could not verify your account." } });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  // 1. Storage: remove everything under <uid>/ in each bucket.
  for (const bucket of BUCKETS) {
    const paths = await listAllFiles(admin, bucket, uid);
    if (paths.length > 0) {
      await admin.storage.from(bucket).remove(paths);
    }
  }

  // 2. The auth user — cascades all DB rows via the FKs.
  const { error: delErr } = await admin.auth.admin.deleteUser(uid);
  if (delErr) {
    return json(500, {
      error: { message: `Could not delete the account: ${delErr.message}` },
    });
  }

  return json(200, { deleted: true });
});
