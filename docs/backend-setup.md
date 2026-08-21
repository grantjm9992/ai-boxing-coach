# Backend setup (Supabase)

The app's persistence + auth backend. Everything client-side reads
`SupabaseConfig` (URL + publishable key); RLS scopes every row to the
signed-in user.

## 1. Database

Run `supabase/migrations/0001_init.sql` in the Supabase dashboard
(**SQL Editor → paste → Run**), or `supabase db push` with the CLI. It creates
the `profiles / sessions / rounds / analyses / keyframes` tables, RLS policies,
the `keyframes / pose / clips` Storage buckets, and the auto-profile trigger.

## 2. Auth providers

**Dashboard → Authentication → Providers.**

- **Email** — enable. (For dev you may also turn off "Confirm email" so sign-up
  logs you straight in.)
- **Google** — enable, paste a Google OAuth client ID + secret (from Google
  Cloud Console → Credentials → OAuth client). Then under
  **Authentication → URL Configuration → Redirect URLs**, add:
  ```
  com.aiboxingcoach.boxing_coach://login-callback
  ```
  This matches `AuthService._oauthRedirect` and the Android manifest
  intent-filter.
- **Apple** — defer until there's an iOS build; needs an Apple Developer
  account (Sign in with Apple key + service ID). Same redirect URL.

## 3. Config in the app

`lib/services/supabase/supabase_config.dart` holds the project URL + publishable
key as defaults (safe to ship — RLS protects the data). Override per-build with:

```
flutter run --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_KEY=…
```

## Storage layout

Blobs live in Storage, referenced by path from the DB rows:

```
keyframes/<uid>/<session>/<segment>/<ts>.jpg
pose/<uid>/<session>/<segment>.pose.json
clips/<uid>/<session>/<segment>.mp4      (later)
```

The first path segment is the user id — the Storage RLS policy keys off it.
