-- ============================================================================
-- 04_seed_admin.sql — Bootstrap the first admin.
-- Run AFTER you have signed up via /gallery/login.html and confirmed your email.
-- ============================================================================

-- 1. Replace this with the email you signed up with.
-- 2. Run this script from the Supabase SQL editor.
-- 3. Verify by selecting from profiles: you should see status = 'admin'.

update public.profiles
set
  status      = 'admin',
  approved_at = now(),
  approved_by = id          -- self-approval for the bootstrap admin
where email = 'YOUR_EMAIL@example.com';

-- Sanity check (will print 1 row if it worked):
select id, email, full_name, status, approved_at
from public.profiles
where email = 'YOUR_EMAIL@example.com';
