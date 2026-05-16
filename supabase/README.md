# Supabase setup for the family gallery

The gallery is gated by Supabase Auth + Postgres Row-Level Security. The frontend is fully static (GitHub Pages compatible). The anon key in `gallery/assets/supabase-client.js` is **public by design** — security is enforced by RLS policies, not by hiding credentials.

## One-time setup

### 1. Create a Supabase project
- Go to [supabase.com](https://supabase.com) and create a new project.
- Note the **Project URL** and **anon/public key** from Project Settings → API.

### 2. Wire credentials into the frontend
Open [gallery/assets/supabase-client.js](../gallery/assets/supabase-client.js) and replace the two placeholders:
```js
const SUPABASE_URL      = 'https://YOUR-PROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-KEY';
```

### 3. Run the SQL files in order
Open Supabase → SQL Editor and run, in this order:
1. `01_schema.sql` — tables, trigger, indexes
2. `02_rls.sql` — Row-Level Security policies
3. `03_storage.sql` — storage bucket + policies

### 4. Configure Auth
In Supabase → Authentication → Settings:
- **Enable email confirmations** (recommended — blocks spam signups before a profile row is even created)
- **Site URL**: set to your deployed URL (e.g. `https://shreyashparajuli.github.io/dr-chaitanya-subba-portfolio/`)
- **Redirect URLs**: add the gallery URL so password reset / confirm links work

### 5. Configure Storage
The `gallery` bucket is created by `03_storage.sql` as private. In Supabase → Storage → `gallery` → Settings:
- Set **Allowed MIME types**: `image/jpeg,image/png,image/webp,image/heic,application/pdf`
- Set **Max file size**: `20MB`

### 6. Bootstrap yourself as admin
1. Sign up on `/gallery/login.html` with your real email
2. Confirm the email
3. Edit `04_seed_admin.sql`, replace `YOUR_EMAIL@example.com` with the email you just used
4. Run it from the SQL Editor

You're now `admin`. Everyone else who signs up will be `pending` until you flip their `profiles.status` to `approved` from the Table Editor.

## Day-to-day: approving someone

1. Relative signs up → confirms email → lands on `/gallery/pending.html`
2. You go to Supabase → Table Editor → `profiles` → find their row → set `status` to `approved`
3. They reload the gallery and have access

No code, no email, no admin UI required for v1. The Edge-Function notification on signup is a separate, optional add-on (see future work below).

## Future work (not in v1)

- Edge Function + Resend integration to email you when someone signs up
- Custom admin page (`/gallery/admin.html`) with approve/disable buttons
- Auto-purge of soft-deleted items after N days
- Thumbnail generation server-side (Supabase Image Transformations)

## Quick reference: schema

| Table | Purpose |
|---|---|
| `auth.users` | Supabase-managed authentication identities |
| `public.profiles` | One row per `auth.users`, holds `status` that gates everything |
| `public.gallery_items` | Gallery metadata; files live in Storage `gallery` bucket |

| Status | Can read gallery? | Can upload? | Can approve others? |
|---|---|---|---|
| `pending` | no | no | no |
| `approved` | yes | yes | no |
| `disabled` | no | no | no |
| `admin` | yes | yes | yes (via dashboard) |
