# Operations — day-to-day admin guide

What to do when something comes up. Most tasks are a few clicks in the Supabase dashboard.

---

## Approving a new family member

When a relative requests access via `/gallery/login.html`:

1. They confirm their email — you don't need to do anything for this step (Gmail SMTP handles it).
2. Their profile lands in the `pending` queue.

To approve:

1. Supabase → **Table Editor → profiles**
2. Find the row for their email — `status` will be `pending`
3. **Double-click** the `status` cell → type `approved` → press Enter

That's it. They can reload the gallery and they're in.

If you want to be tidier, also fill in `approved_at` (set to `now()`) and `approved_by` (your own UUID — copy from your row). Not strictly required; the column update fires the relevant policy regardless.

### Bulk approval via SQL

If multiple people sign up at once, faster to do it in SQL Editor:

```sql
update public.profiles
set status      = 'approved',
    approved_at = now(),
    approved_by = (select id from public.profiles where status = 'admin' limit 1)
where email in (
  'aunt@example.com',
  'cousin@example.com',
  'uncle@example.com'
);
```

---

## Recovering a deleted photo or document

Soft delete only hides the item — both the database row and the file in Storage stay intact. To restore:

### Via Table Editor (single item)

1. Supabase → **Table Editor → gallery_items**
2. Find the row — deleted items have a value in the `deleted_at` column
3. Edit the row: set `deleted_at` and `deleted_by` both to `NULL`
4. Save

The item reappears in the gallery feed.

### Via SQL Editor (multiple items)

See what's in the trash:

```sql
select id, title, uploader_id, deleted_at
from public.gallery_items
where deleted_at is not null
order by deleted_at desc;
```

Restore a specific item by ID:

```sql
update public.gallery_items
set deleted_at = null, deleted_by = null
where id = 'paste-uuid-here';
```

Restore everything ever deleted (use cautiously):

```sql
update public.gallery_items
set deleted_at = null, deleted_by = null
where deleted_at is not null;
```

---

## Permanently deleting a photo (to free space)

Soft-deleted items still occupy storage. To actually free space:

1. Supabase → **Table Editor → gallery_items** → find the row → note the `storage_path` value (e.g. `abc.../def...jpg`)
2. Supabase → **Storage → gallery** → navigate to that path → delete the file
3. Back in Table Editor → delete the `gallery_items` row (admin-only via RLS)

Only do this for truly unwanted items. The soft-delete trash is the safety net — once you hard-delete, it's gone.

---

## Disabling someone's access

If a family member needs to be temporarily blocked (e.g. account compromised):

1. Supabase → **Table Editor → profiles** → find their row
2. Set `status` to `disabled`
3. Save

Effect: they're signed out on next page load, the route guard redirects them to the login page, and RLS blocks all reads/writes regardless of session state.

To re-enable: flip `status` back to `approved`.

---

## Removing someone entirely

If you want them gone with no trace (rare):

1. Supabase → **Authentication → Users** → find them → three-dot menu → **Delete user**

This cascade-deletes their `profiles` row (via the foreign key with `on delete cascade`). Note: their uploaded photos remain in `gallery_items` with their now-invalid `uploader_id`. You probably want to either:

- Reassign their uploads to your admin account first (so they're attributed but stay), or
- Soft-delete or hard-delete their items first.

---

## Checking current usage

Supabase → **Project Settings → Usage** shows current consumption against the free-tier caps:

- File storage: out of 1 GB
- Bandwidth: out of 5 GB/month (resets monthly)
- Database size: out of 500 MB

Worth checking once a month for a family site. At 70–80% on storage, consider:
- Hard-deleting old soft-deleted items
- Dropping the resize cap from 2000px to 1500px in [`gallery/assets/image-process.js`](../gallery/assets/image-process.js)
- Moving storage to a cheaper provider (Cloudflare R2 has 10 GB free with no egress fees)

---

## Verifying the keep-alive is working

```sql
select last_ping, ping_count from public.keepalive_log;
```

Expectations:

- `last_ping` is from sometime today (or yesterday, depending on UTC offset)
- `ping_count` increments by ~1 each day

If `last_ping` is days old, the GitHub Action isn't running. Check:

1. Repo → **Actions** tab → **Supabase keep-alive** — recent runs visible?
2. If no recent runs, GitHub may have disabled the schedule (happens after 60 days of no commits). Push any commit to re-arm.
3. If runs are failing, click into one to see the error — most likely Supabase credentials or the function name.

---

## Restoring a paused Supabase project

If you ever open the dashboard and see "Project paused":

1. Click **Restore project**
2. Wait ~60 seconds
3. Refresh the gallery — back online

All data (photos, profiles, gallery_items) is preserved across pauses. No migration needed.

Paused projects sit dormant; Supabase keeps them recoverable for ~90 days. After that, free-tier paused projects may be deleted. So: don't let the pause sit for months. The keep-alive workflow prevents pauses from happening in the first place, but if it ever fails, restore promptly.

---

## Updating memorial content

The memorial site is a single file: [`index.html`](../index.html). To update:

1. Edit the relevant section
2. Test locally (`python -m http.server 8000`)
3. Commit and push to `main`

GitHub Pages auto-deploys; changes are live within ~1 minute.

### Common edits

| Want to… | Find the section in `index.html` |
|---|---|
| Update biography text | Search for `<section id="biography"` |
| Add a publication | Search for `<section id="publications"` |
| Add/edit a timeline entry | Search for `class="timeline"` |
| Update tribute quotes | Search for `<blockquote class="blockquote-pull"` |
| Add Nepali translations for new strings | Update the `STRINGS` dictionary near the bottom |

---

## Email troubleshooting

### Family member says they didn't get a confirmation email

1. Have them check spam — Gmail-to-Gmail rarely lands there, but anything else might
2. Supabase → **Authentication → Users** — is their row there?
   - If yes, `email_confirmed_at` is empty → email send failed. Re-send from the three-dot menu, or **manually confirm** them from the same menu
   - If no, the signup never reached Supabase — they may have hit a network error. Have them try again

### "Email rate limit exceeded"

The custom SMTP (Gmail App Password) has a soft limit of ~500 emails/day. If a stranger or bot is hammering signups, switch the SMTP to a more rate-limit-tolerant provider, or temporarily disable signups by setting `auth.allow_signups` to `false` in Supabase Authentication settings.

If you ever see this error in normal use, something's wrong — investigate before blindly raising limits.

---

## Updating the schema

If you ever change the database schema (e.g. adding a column or table), the workflow is:

1. Edit the relevant SQL file in `supabase/`
2. Test it on a throwaway Supabase project first if possible
3. Run the new SQL against production via Supabase SQL Editor
4. If frontend changes are needed (e.g. new column in upload form), update the relevant `gallery/` files and push to GitHub Pages

The SQL files are written to be idempotent — re-running shouldn't error. Add `if not exists` / `or replace` to anything new.

---

## Backups

Currently no automated backups beyond what Supabase provides server-side (the free tier does not guarantee point-in-time recovery; the Pro tier does daily backups for 7 days).

For irreplaceable photos, consider one of:

- **Manual periodic export:** download all files from Storage occasionally (a one-off script can do this)
- **A second cloud bucket:** upload duplicates to a Cloudflare R2 / Backblaze B2 free-tier bucket
- **Upgrade to Supabase Pro:** $25/month, includes daily automated backups

Worth setting up once the gallery contains content the family genuinely couldn't replace.

---

## Quick reference: status values

| Status | Meaning | Can read gallery? | Can upload? |
|---|---|---|---|
| `pending` | New signup, awaiting approval | No | No |
| `approved` | Family member, full access | Yes | Yes (own + read all) |
| `disabled` | Manually blocked | No | No |
| `admin` | You | Yes | Yes (can delete any) |
