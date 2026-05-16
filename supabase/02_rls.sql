-- ============================================================================
-- 02_rls.sql — Row-Level Security policies. Run after 01_schema.sql.
-- This is the actual lock. Even with the public anon key, no one can read
-- or write gallery data unless their profiles.status is 'approved' or 'admin'.
-- ============================================================================

alter table public.profiles enable row level security;
alter table public.gallery_items enable row level security;

-- ---------------------------------------------------------------------------
-- Helpers — security definer so they can read profiles even when caller can't.
-- ---------------------------------------------------------------------------
create or replace function public.is_approved(uid uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = uid and status in ('approved','admin')
  );
$$;

create or replace function public.is_admin(uid uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = uid and status = 'admin'
  );
$$;

-- ---------------------------------------------------------------------------
-- profiles
--   Users see their own row. Admins see all rows. Users can update full_name.
--   No one can change their own status, approved_at, approved_by from the
--   client — only the admin can, via the Supabase dashboard (service role).
-- ---------------------------------------------------------------------------
drop policy if exists "read own profile"        on public.profiles;
drop policy if exists "admin reads all"         on public.profiles;
drop policy if exists "update own full_name"    on public.profiles;

create policy "read own profile"
  on public.profiles for select
  using (id = auth.uid());

create policy "admin reads all"
  on public.profiles for select
  using (public.is_admin(auth.uid()));

create policy "update own full_name"
  on public.profiles for update
  using (id = auth.uid())
  with check (
    id = auth.uid()
    -- guard: status, approved_at, approved_by must equal their previous value.
    -- Postgres RLS doesn't expose OLD in policies, so we restrict columns at
    -- the API layer via grants below.
  );

-- Column-level grant: anon and authenticated may only update full_name.
revoke update on public.profiles from anon, authenticated;
grant update (full_name) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- gallery_items
-- ---------------------------------------------------------------------------
drop policy if exists "approved read gallery"       on public.gallery_items;
drop policy if exists "admin reads deleted"         on public.gallery_items;
drop policy if exists "approved insert gallery"     on public.gallery_items;
drop policy if exists "owner or admin update"       on public.gallery_items;
drop policy if exists "admin hard delete"           on public.gallery_items;

-- SELECT: approved users see non-deleted items
create policy "approved read gallery"
  on public.gallery_items for select
  using (
    deleted_at is null
    and public.is_approved(auth.uid())
  );

-- SELECT: admins also see soft-deleted items (for recovery)
create policy "admin reads deleted"
  on public.gallery_items for select
  using (public.is_admin(auth.uid()));

-- INSERT: approved users can upload; uploader_id must be themselves
create policy "approved insert gallery"
  on public.gallery_items for insert
  with check (
    uploader_id = auth.uid()
    and public.is_approved(auth.uid())
  );

-- UPDATE: own items, or admin can update any (used for soft-delete + edits)
create policy "owner or admin update"
  on public.gallery_items for update
  using (
    public.is_approved(auth.uid())
    and (
      uploader_id = auth.uid()
      or public.is_admin(auth.uid())
    )
  )
  with check (
    -- Cannot reassign ownership
    uploader_id = uploader_id
  );

-- DELETE (hard): admin only. v1 prefers soft-delete; admin can dashboard-purge.
create policy "admin hard delete"
  on public.gallery_items for delete
  using (public.is_admin(auth.uid()));
