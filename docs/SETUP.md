# Setup — from a clean clone to a running site

This walks through everything needed to take a fresh clone of this repository and produce a fully working memorial site + family gallery on the open internet.

Estimated time: **45–60 minutes** end-to-end. Most of it is waiting for Supabase to provision and for DNS/email propagation.

---

## 0. Prerequisites

- A GitHub account
- An email address for Supabase, Gmail SMTP, and the admin login
- Python or any local web server for testing (Python 3 is built into most systems)

---

## 1. Clone & serve locally

```bash
git clone https://github.com/<your-account>/dr-chaitanya-subba-portfolio.git
cd dr-chaitanya-subba-portfolio
python -m http.server 8000
```

Open `http://127.0.0.1:8000/` — the memorial site should load. The gallery pages will load too but will fail to authenticate until Supabase is wired up (next sections).

---

## 2. Create a Supabase project

1. Go to https://supabase.com and sign in (GitHub login works).
2. Click **New project**.
3. Settings:
   - **Name:** anything memorable (e.g. `dr-subba-family-gallery`)
   - **Database password:** generate a strong one and save it somewhere safe
   - **Region:** geographically near you
4. Wait ~2 minutes for the project to provision.

When it's ready, go to **Project Settings → API**. You'll need:

- **Project URL** (e.g. `https://abcdefgh.supabase.co`)
- **anon public** key — newer Supabase calls this the **publishable key** (starts with `sb_publishable_...`)

These are public credentials by design. **Do not copy the service_role key for anything in this project** — that key bypasses Row-Level Security and is admin-only.

---

## 3. Wire credentials into the frontend

Open [`gallery/assets/supabase-client.js`](../gallery/assets/supabase-client.js). Replace the two placeholder constants near the top:

```js
const SUPABASE_URL      = 'https://YOUR-PROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-KEY';
```

with your real values. Save. No restart needed — just reload any open browser tab.

---

## 4. Run the SQL files in order

Open Supabase → **SQL Editor** → **New query**. For each file below, paste the contents into the editor and click **Run** (or press Ctrl+Enter).

| Order | File | Purpose |
|---|---|---|
| 1 | [`supabase/01_schema.sql`](../supabase/01_schema.sql) | Creates `profiles`, `gallery_items`, auto-trigger, indexes |
| 2 | [`supabase/02_rls.sql`](../supabase/02_rls.sql) | Enables RLS and adds all policies |
| 3 | [`supabase/03_storage.sql`](../supabase/03_storage.sql) | Creates the private `gallery` bucket + storage policies |
| 4 | [`supabase/05_keepalive.sql`](../supabase/05_keepalive.sql) | Creates the keep-alive function (anti-pause) |

Each should run silently with no errors. The files are idempotent — re-running is safe. **Do not run `04_seed_admin.sql` yet** — that comes after your own signup.

---

## 5. Configure Auth settings in Supabase

### 5a. Email confirmation

Supabase → **Authentication → Sign In / Up → Email** → confirm **"Enable email confirmations"** is **on**. This means new signups must click a link in their email before they can log in — useful for filtering out spam.

### 5b. Site URL and Redirect URLs

Supabase → **Authentication → URL Configuration**:

- **Site URL:** set to the URL where the site will live. For GitHub Pages this is typically:
  ```
  https://<your-github-username>.github.io/dr-chaitanya-subba-portfolio
  ```
- **Redirect URLs:** add both:
  ```
  https://<your-github-username>.github.io/dr-chaitanya-subba-portfolio/gallery/login.html
  http://127.0.0.1:8000/gallery/login.html
  ```

The localhost entry keeps local development working without changing settings every time.

### 5c. Storage bucket settings

Supabase → **Storage → gallery → Settings**:

- **Allowed MIME types:** `image/jpeg,image/png,image/webp,image/heic,application/pdf`
- **Max file size:** `20 MB`

The SQL has already set the bucket to private. Don't make it public.

---

## 6. Configure SMTP (for confirmation emails)

By default, Supabase ships with a built-in mailer that's rate-limited to ~4 emails per hour. That's not enough for real family use. Plug in a real provider.

### Recommended: Gmail SMTP via App Password

This uses a dedicated Gmail account that you create just for sending notifications (you should not reuse your personal Gmail for this).

1. **Create a dedicated Gmail account** at https://accounts.google.com/signup. Something like `your-name.notify@gmail.com` so it can be reused across other projects.
2. **Enable 2-Step Verification** at https://myaccount.google.com/security. (Required for the next step.)
3. **Generate an App Password** at https://myaccount.google.com/apppasswords:
   - Name: `Supabase Family Gallery`
   - Click **Create**, copy the 16-character password Google shows. **Save it now** — Google won't show it again.

4. Back in Supabase → **Project Settings → Authentication → SMTP Settings** → enable **"Custom SMTP"**:

   | Field | Value |
   |---|---|
   | Sender email | the new Gmail address |
   | Sender name | `Dr. Chaitanya Subba Family Gallery` |
   | Host | `smtp.gmail.com` |
   | Port | `587` |
   | Username | the new Gmail address |
   | Password | the 16-char App Password (remove spaces) |
   | Minimum interval | `1` |

5. **Save**, then click **Send test email** if available. Otherwise, sign up a test account at `/gallery/login.html` and verify an email arrives.

If you don't yet have a custom domain, this is the most reliable free path. The "From" line will read your project name + the helper Gmail address, which family will recognize.

---

## 7. Bootstrap yourself as admin

1. Open `http://127.0.0.1:8000/gallery/login.html` (or the live URL) → **Request access** tab → use your real email.
2. Check your inbox for a confirmation email from your new SMTP setup → click the confirmation link.
3. You should land on `pending.html`. Good — that means the signup worked and the auto-trigger inserted a `profiles` row with `status='pending'`.
4. Open [`supabase/04_seed_admin.sql`](../supabase/04_seed_admin.sql) → replace `YOUR_EMAIL@example.com` with the email you just used.
5. Run it in the Supabase SQL Editor. The `SELECT` at the bottom should return one row with `status = 'admin'`.
6. Reload the gallery page — you should now land on `gallery/index.html` as admin.

---

## 8. Push to GitHub and enable Pages

```bash
git add .
git commit -m "Initial setup"
git push origin main
```

Then on GitHub:

1. Repo → **Settings → Pages**
2. **Source:** Deploy from a branch
3. **Branch:** `main` / `/ (root)`
4. **Save**

After ~30 seconds, GitHub shows the live URL. The memorial site is now public; the gallery is gated by the auth flow you've already wired.

---

## 9. Enable the keep-alive workflow

GitHub Actions on a public repo is free with unlimited minutes. The workflow defined in [`.github/workflows/keepalive.yml`](../.github/workflows/keepalive.yml) will:

- Run automatically every day at 04:17 UTC
- Call `public.keepalive()` on Supabase
- Keep the project's 7-day inactivity pause from triggering

Make sure the workflow file's `SUPABASE_URL` and `SUPABASE_ANON_KEY` env values match the credentials you used in step 3. If you're forking this project for your own use, update them.

To test it manually:

1. Repo → **Actions** tab → **Supabase keep-alive** (left sidebar)
2. **Run workflow** → choose `main` → **Run workflow**
3. Wait ~10 seconds → refresh → the run should show a green check
4. Verify in Supabase SQL Editor:
   ```sql
   select * from public.keepalive_log;
   ```
   You should see `ping_count` ≥ 1 and `last_ping` from the last few seconds.

---

## 10. Smoke test the full family flow

In an **incognito window** so you're not signed in:

1. Open the live URL → click **Family Gallery** in the nav → land on `/gallery/login.html`.
2. Use the **Request access** tab with a different email you control (or a `+test` alias of your Gmail).
3. Check the inbox for a confirmation email → click → land on `pending.html`.
4. In your regular window, in Supabase Table Editor: change the new profile's `status` to `approved`.
5. Reload the incognito tab → you should now see the gallery with the "Add to gallery" button visible.

Upload a photo and confirm:

- The tile appears in the grid.
- The file in Supabase Storage has no EXIF GPS data (use https://exif.tools to verify).
- Deleting it makes it disappear from the grid but the row remains in `gallery_items` with `deleted_at` populated.

If all of that works, you're live.

---

## Common setup snags

**"Email sending error" or rate-limited:** SMTP isn't configured yet (or the test account is on Resend's free tier with the verified-recipient restriction). Switch to Gmail SMTP as in step 6.

**Confirmation link redirects to the wrong URL:** Site URL in step 5b is wrong. Update and have the user request a new confirmation.

**Gallery page says "Could not load profile":** The `profiles` row doesn't exist. Either `01_schema.sql` didn't run, or the auto-trigger isn't installed. Check Supabase → SQL Editor:
```sql
select tgname from pg_trigger where tgname = 'on_auth_user_created';
```
Should return one row.

**Upload returns 403 / RLS error:** The user's profile isn't `approved` (or `admin`). Check the `status` column in `profiles`.

**Gallery is empty even for admin:** Either no items uploaded yet (expected), or all items have `deleted_at` populated (check the table). Soft-deleted items don't show.

**Workflow run fails with "Unexpected response":** The `keepalive` function isn't installed. Run `05_keepalive.sql`.

---

See [docs/OPERATIONS.md](OPERATIONS.md) for ongoing administration and [docs/ARCHITECTURE.md](ARCHITECTURE.md) for the technical design.
