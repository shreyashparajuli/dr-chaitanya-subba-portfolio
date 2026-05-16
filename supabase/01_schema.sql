-- ============================================================================
-- 01_schema.sql — Tables, trigger, indexes for the family gallery.
-- Idempotent: safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- profiles
--   One row per auth.users. The status column gates everything via RLS.
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         text not null,
  full_name     text,
  status        text not null default 'pending'
                check (status in ('pending','approved','disabled','admin')),
  requested_at  timestamptz not null default now(),
  approved_at   timestamptz,
  approved_by   uuid references auth.users(id)
);

create index if not exists profiles_status_idx on public.profiles (status);

-- ---------------------------------------------------------------------------
-- Auto-create a pending profile when a new auth.users row appears.
-- security definer so it can write into public.profiles regardless of RLS.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', null)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- gallery_items
--   Metadata for each item. Files live in Storage bucket "gallery".
--   storage_path is "{user_id}/{uuid}.{ext}" — enforced by storage policies.
--   deleted_at powers soft delete.
-- ---------------------------------------------------------------------------
create table if not exists public.gallery_items (
  id            uuid primary key default gen_random_uuid(),
  uploader_id   uuid not null references auth.users(id),
  title         text not null check (length(title) between 1 and 200),
  caption       text check (caption is null or length(caption) <= 2000),
  storage_path  text not null,
  media_type    text not null check (media_type in ('photo','document')),
  category      text not null check (category in (
                  'family',
                  'awards',
                  'publications',
                  'documents',
                  'other'
                )),
  taken_on      date,
  created_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  deleted_by    uuid references auth.users(id)
);

-- Hot path: list newest non-deleted items by category
create index if not exists gallery_items_feed_idx
  on public.gallery_items (created_at desc)
  where deleted_at is null;

create index if not exists gallery_items_category_idx
  on public.gallery_items (category, created_at desc)
  where deleted_at is null;

create index if not exists gallery_items_uploader_idx
  on public.gallery_items (uploader_id, created_at desc);
