-- AI Boxing Coach — initial backend schema.
--
-- Shape mirrors the on-device model: a user runs sessions; a session has
-- rounds; a round has one analysis (offline rules, optionally enriched by an AI
-- model) and a handful of keyframe images. Large blobs (keyframe JPEGs, the
-- pose sequence JSON) live in Storage — rows only hold their paths + the
-- metadata we actually query.
--
-- Every table carries user_id (denormalised) so Row-Level Security is a trivial
-- `user_id = auth.uid()` on each — no joins in policies, fast and obvious.

-- ---------------------------------------------------------------------------
-- profiles: 1:1 with auth.users. Mirrors the app's UserProfile.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text,
  stance        text,
  style         text,
  school        text,
  analysis_mode text not null default 'offline',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- sessions: one workout run. client_session_id is the app's timestamp-based
-- id, kept unique per user so uploads are idempotent (upsert on re-send).
-- ---------------------------------------------------------------------------
create table public.sessions (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users (id) on delete cascade,
  client_session_id text not null,
  title             text,
  plan              jsonb,          -- the SessionPlan / template snapshot
  started_at        timestamptz not null default now(),
  ended_at          timestamptz,
  created_at        timestamptz not null default now(),
  unique (user_id, client_session_id)
);
create index sessions_user_started_idx
  on public.sessions (user_id, started_at desc);

-- ---------------------------------------------------------------------------
-- rounds: a recorded technical round within a session. pose_path points at the
-- pose sequence JSON in Storage; clip_path is optional (video is retained
-- locally for 7 days — we can start uploading it later without a schema change).
-- ---------------------------------------------------------------------------
create table public.rounds (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  session_id      uuid not null references public.sessions (id) on delete cascade,
  segment_index   int  not null,
  phase           text,
  round_number    int,
  rounds_in_phase int,
  title           text,
  duration_ms     int,
  recorded_at     timestamptz not null default now(),
  pose_path       text,           -- Storage: pose bucket
  clip_path       text,           -- Storage: clips bucket (optional, later)
  created_at      timestamptz not null default now(),
  unique (session_id, segment_index)
);
create index rounds_session_idx on public.rounds (session_id, segment_index);

-- ---------------------------------------------------------------------------
-- analyses: the RoundAnalysis for a round. One row holds the offline rules
-- result and, when an AI mode ran, its coaching too (ai_coaching / model).
-- Queryable bits are columns; the rich structures stay as JSONB.
-- ---------------------------------------------------------------------------
create table public.analyses (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  round_id       uuid not null references public.rounds (id) on delete cascade,
  mode           text not null default 'offline',   -- offline | keyframe | full_frame
  summary        text,
  metrics        jsonb,          -- mechanical facts (frames, punch count, ...)
  corrections    jsonb,          -- correctionPriorities[]
  positive_notes jsonb,          -- positiveNotes[]
  ai_coaching    text,           -- modelCoaching, null when offline
  model          text,           -- e.g. gemini-3.6-flash
  created_at     timestamptz not null default now(),
  unique (round_id)
);

-- ---------------------------------------------------------------------------
-- keyframes: the images pulled from a round (flagged moments / AI frames).
-- Bytes live in Storage; the row says where and what it illustrates.
-- ---------------------------------------------------------------------------
create table public.keyframes (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  round_id       uuid not null references public.rounds (id) on delete cascade,
  storage_path   text not null,  -- Storage: keyframes bucket
  timestamp_ms   int not null,
  correction_ref text,           -- which correction this frame illustrates
  mime           text not null default 'image/jpeg',
  created_at     timestamptz not null default now()
);
create index keyframes_round_idx on public.keyframes (round_id, timestamp_ms);

-- ---------------------------------------------------------------------------
-- Row-Level Security: owner-only access on every table.
-- ---------------------------------------------------------------------------
alter table public.profiles  enable row level security;
alter table public.sessions  enable row level security;
alter table public.rounds    enable row level security;
alter table public.analyses  enable row level security;
alter table public.keyframes enable row level security;

create policy "own profile" on public.profiles
  for all using (id = auth.uid()) with check (id = auth.uid());

create policy "own sessions" on public.sessions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own rounds" on public.rounds
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own analyses" on public.analyses
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own keyframes" on public.keyframes
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Auto-create a profile row when a user signs up.
-- ---------------------------------------------------------------------------
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name')
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Storage buckets (private) + owner-only policies. First path segment is the
-- user id, e.g. keyframes/<uid>/<session>/<segment>/<ts>.jpg
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('keyframes', 'keyframes', false),
       ('pose', 'pose', false),
       ('clips', 'clips', false)
on conflict (id) do nothing;

create policy "own storage objects"
  on storage.objects for all
  using (
    bucket_id in ('keyframes', 'pose', 'clips')
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id in ('keyframes', 'pose', 'clips')
    and (storage.foldername(name))[1] = auth.uid()::text
  );
