-- ============================================================================
-- 05_keepalive.sql — Prevents the 7-day free-tier inactivity pause.
--
-- Creates a single-row tracker table and a public RPC function that updates
-- it. A scheduled GitHub Action calls the function daily, which counts as
-- database write activity and keeps the project awake.
--
-- After running this once, you can verify it's working with:
--   select * from public.keepalive_log;
-- ============================================================================

-- Single-row tracker. The check constraint pins id=1 so there can only ever
-- be one row no matter how the keep-alive is called.
create table if not exists public.keepalive_log (
  id          int primary key default 1,
  last_ping   timestamptz not null default now(),
  ping_count  bigint      not null default 0,
  constraint single_row check (id = 1)
);

insert into public.keepalive_log (id)
values (1)
on conflict (id) do nothing;

-- Public RPC. Returns 'pong' for the caller; the side-effect is an UPDATE,
-- which is what Supabase counts as activity.
create or replace function public.keepalive()
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.keepalive_log
  set last_ping  = now(),
      ping_count = ping_count + 1
  where id = 1;
  return 'pong';
end;
$$;

-- Anyone can call it (anon + signed-in users). The function is read-only
-- from the caller's POV — they can't write to keepalive_log directly.
grant execute on function public.keepalive() to anon, authenticated;

-- RLS off for keepalive_log: only the function (running as definer) ever
-- writes to it, and no one needs to read it through the API directly. We
-- still leave SELECT permission off for safety.
alter table public.keepalive_log enable row level security;
-- (no policies = nobody can read or write via the REST API, only the
--  security-definer function above can modify it)
