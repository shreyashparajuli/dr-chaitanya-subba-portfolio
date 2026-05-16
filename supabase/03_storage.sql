-- ============================================================================
-- 03_storage.sql — Storage bucket + policies. Run after 02_rls.sql.
-- File paths follow "{user_id}/{uuid}.{ext}" so ownership is path-derived.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Bucket: private (not public-readable). Files are served via signed URLs
-- so even leaked URLs expire.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('gallery', 'gallery', false)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Storage object policies
-- ---------------------------------------------------------------------------
drop policy if exists "approved read storage"          on storage.objects;
drop policy if exists "approved upload storage"        on storage.objects;
drop policy if exists "owner or admin delete storage"  on storage.objects;
drop policy if exists "owner update storage"           on storage.objects;

-- SELECT (i.e. download / signed URL): approved users on the gallery bucket
create policy "approved read storage"
  on storage.objects for select
  using (
    bucket_id = 'gallery'
    and public.is_approved(auth.uid())
  );

-- INSERT: approved users may upload, but only into a folder matching their uid
create policy "approved upload storage"
  on storage.objects for insert
  with check (
    bucket_id = 'gallery'
    and public.is_approved(auth.uid())
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- UPDATE (rare — e.g. metadata): owner only
create policy "owner update storage"
  on storage.objects for update
  using (
    bucket_id = 'gallery'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- DELETE: owner of the file, or admin
create policy "owner or admin delete storage"
  on storage.objects for delete
  using (
    bucket_id = 'gallery'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin(auth.uid())
    )
  );
