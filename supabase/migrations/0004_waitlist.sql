-- Marketing-site waitlist — the beta / coach / hardware signup forms POST here.
--
-- Anonymous visitors may INSERT (they have no account), but nobody may read the
-- list through the API: there is deliberately no SELECT policy, so emails are
-- readable only via the dashboard / service role. `list` distinguishes the
-- three forms (app_beta, coach_beta, hardware).

create table public.waitlist (
  id         uuid primary key default gen_random_uuid(),
  email      text not null,
  list       text not null default 'app_beta',
  source     text,                       -- optional page/campaign tag
  created_at timestamptz not null default now(),
  unique (email, list)
);

alter table public.waitlist enable row level security;

-- Allow inserts from the public (publishable/anon) key and signed-in users.
grant insert on public.waitlist to anon, authenticated;

create policy "anyone can join the waitlist" on public.waitlist
  for insert
  to anon, authenticated
  with check (
    email is not null
    and char_length(email) between 3 and 320
    and list in ('app_beta', 'coach_beta', 'hardware')
  );
