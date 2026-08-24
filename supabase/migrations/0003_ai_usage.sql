-- AI usage metering — enforces the free-tier "3 AI analyses / user / week".
--
-- The cap lives here (SQL), not on the device: a client-side limit is bypassed
-- by a reinstall or a clock change. The `analyze` edge function reserves a unit
-- before calling the paid model and refunds it if the model call fails, so a
-- failed request never burns a user's weekly allowance.

-- One row per user per ISO week (weeks start Monday, UTC).
create table public.ai_usage (
  user_id    uuid not null references auth.users (id) on delete cascade,
  week_start date not null,
  count      int  not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, week_start)
);

alter table public.ai_usage enable row level security;

-- Users may read their own usage (e.g. a "2 of 3 left this week" hint in the
-- UI). Writes only ever happen through the security-definer functions below,
-- so there is deliberately no insert/update policy.
create policy "own ai usage" on public.ai_usage
  for select using (user_id = auth.uid());

-- Monday 00:00 UTC of the current week, as a date.
create or replace function public.current_ai_week()
returns date
language sql
stable
as $$
  select (date_trunc('week', (now() at time zone 'utc')))::date;
$$;

-- Atomically consume one unit of the caller's weekly AI quota.
-- Returns the number of analyses REMAINING after this one (>= 0).
-- Raises `ai_quota_exceeded` when the weekly cap is already reached.
create or replace function public.consume_ai_quota(p_weekly_limit int default 3)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_week  date := current_ai_week();
  v_count int;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- Insert the first use of the week, or increment only while under the cap.
  -- If a row exists at the cap, the WHERE blocks the update, nothing is
  -- returned, and v_count stays null -> we raise below.
  insert into public.ai_usage (user_id, week_start, count)
    values (v_uid, v_week, 1)
  on conflict (user_id, week_start) do update
    set count = ai_usage.count + 1, updated_at = now()
    where ai_usage.count < p_weekly_limit
  returning count into v_count;

  if v_count is null then
    raise exception 'weekly AI limit reached'
      using errcode = 'P0001', detail = 'ai_quota_exceeded';
  end if;

  return greatest(p_weekly_limit - v_count, 0);
end;
$$;

-- Give back one unit (used by the edge function when the model call fails after
-- a successful reserve). Never drops below zero, only touches the current week.
create or replace function public.refund_ai_quota()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_week date := current_ai_week();
begin
  update public.ai_usage
    set count = greatest(count - 1, 0), updated_at = now()
    where user_id = v_uid and week_start = v_week;
end;
$$;

-- Read-only: how many analyses the caller has left this week (for the UI).
create or replace function public.ai_quota_remaining(p_weekly_limit int default 3)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select greatest(
    p_weekly_limit - coalesce(
      (select count from public.ai_usage
        where user_id = auth.uid() and week_start = current_ai_week()),
      0),
    0);
$$;

-- Only signed-in users may call these; the anon/publishable role may not.
revoke all on function public.consume_ai_quota(int)   from public, anon;
revoke all on function public.refund_ai_quota()        from public, anon;
revoke all on function public.ai_quota_remaining(int)  from public, anon;
grant execute on function public.consume_ai_quota(int)  to authenticated;
grant execute on function public.refund_ai_quota()       to authenticated;
grant execute on function public.ai_quota_remaining(int) to authenticated;
