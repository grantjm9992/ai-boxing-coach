-- Sparring mode — its own tables and Storage bucket, separate from the
-- single-person sessions / rounds / analyses / keyframes. See docs/SPARRING.md.
--
-- A user runs sparring sessions; a session has rounds; each round has two
-- fighter rows (A = the user once they've said which one they are, B their
-- partner) with that fighter's measurements and corrections. Pose sequences
-- live in the `sparring` bucket. Every table carries user_id so RLS is a plain
-- `user_id = auth.uid()`, like the rest of the schema. The AI review draws on
-- the same ai_usage allowance (via the `sparring` edge function).

create table public.sparring_sessions (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users (id) on delete cascade,
  client_session_id text not null,
  started_at        timestamptz not null default now(),
  settings          jsonb,          -- rounds, round / rest length, AI review on
  partner_name      text,
  identified        boolean not null default false,  -- user said which one they are
  created_at        timestamptz not null default now(),
  unique (user_id, client_session_id)
);
create index sparring_sessions_user_started_idx
  on public.sparring_sessions (user_id, started_at desc);

create table public.sparring_rounds (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  session_id     uuid not null references public.sparring_sessions (id) on delete cascade,
  round_number   int  not null,
  recorded_at    timestamptz not null default now(),
  duration_ms    int,
  unresolved_ms  jsonb,           -- per fighter: time not analysed (clinches…)
  interaction    jsonb,           -- distance bands, exchanges, counters, …
  ai_report      jsonb,           -- the AI coach's report, when it ran
  mode           text not null default 'offline',  -- offline | full_frame
  created_at     timestamptz not null default now(),
  unique (session_id, round_number)
);
create index sparring_rounds_session_idx on public.sparring_rounds (session_id, round_number);

create table public.sparring_fighters (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  round_id      uuid not null references public.sparring_rounds (id) on delete cascade,
  label         text not null check (label in ('a', 'b')),
  is_user       boolean not null default false,
  display_name  text,
  metrics       jsonb,            -- stance, punches, per minute, punch mix
  findings      jsonb,            -- shown corrections
  strengths     jsonb,
  summary       text,             -- the AI coach's read of this fighter
  pose_path     text,             -- Storage: sparring bucket
  created_at    timestamptz not null default now(),
  unique (round_id, label)
);

alter table public.sparring_sessions enable row level security;
alter table public.sparring_rounds   enable row level security;
alter table public.sparring_fighters enable row level security;

create policy "own sparring sessions" on public.sparring_sessions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own sparring rounds" on public.sparring_rounds
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own sparring fighters" on public.sparring_fighters
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Private bucket; first path segment is the user id:
-- sparring/<uid>/<session>/r<n>/fighter_<a|b>.json
insert into storage.buckets (id, name, public)
values ('sparring', 'sparring', false)
on conflict (id) do nothing;

create policy "own sparring objects"
  on storage.objects for all
  using (
    bucket_id = 'sparring'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'sparring'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
