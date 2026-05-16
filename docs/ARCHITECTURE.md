# Architecture

How the system fits together. This document is for understanding *why* the project is structured the way it is — useful for future maintenance, extension, or migration.

---

## High-level diagram

```
                       Browser (family member)
                              │
              ┌───────────────┴───────────────┐
              │                               │
              ▼                               ▼
   GitHub Pages (static)            Supabase (BaaS)
   ─────────────────────            ─────────────────────
   index.html (memorial)            auth.users
   gallery/login.html               ├── (managed by Supabase Auth)
   gallery/pending.html             │
   gallery/index.html               public.profiles
   gallery/assets/*.js              ├── id  (FK → auth.users)
   gallery/assets/*.css             ├── status (pending|approved|disabled|admin)
                                    └── (gated by RLS)
                                    
                                    public.gallery_items
                                    ├── uploader_id, title, caption
                                    ├── storage_path, media_type, category
                                    ├── deleted_at (soft delete)
                                    └── (gated by RLS)
                                    
                                    public.keepalive_log
                                    └── (single row, updated daily)
                                    
                                    storage.objects (gallery bucket)
                                    ├── files at "<user_id>/<uuid>.<ext>"
                                    └── (gated by RLS + signed URLs)


              GitHub Actions (cron)
              ─────────────────────────
              keepalive.yml — daily at 04:17 UTC
              └── calls public.keepalive() via REST
```

The memorial site and the gallery share the same origin and styling but are independent at the data level: the memorial is fully static HTML; the gallery is a small dynamic client talking to Supabase.

---

## Design principles

A few decisions worth calling out, because they shaped everything else:

### 1. Static frontend + BaaS backend (no custom server)

The whole site, including the gallery, is served as static files from GitHub Pages. There is no Node/Express/Django/whatever server to maintain. All dynamic behavior (auth, queries, uploads) happens via direct browser-to-Supabase HTTP requests.

**Why:** zero ops burden, no deployment pipeline beyond `git push`, and the security perimeter is small enough to reason about end-to-end.

**Trade-off:** the Supabase URL + publishable key are public (committed to the repo). This is fine *only because* Row-Level Security enforces every access at the database level. The publishable key is the standard way Supabase apps work; the threat model assumes it's exposed.

### 2. Row-Level Security as the only real lock

The frontend has route guards (`requireApproved()` in `auth.js`) and the UI hides admin-only controls from non-admins. **Neither of these is a security boundary.** They exist for UX. The actual access control is at the database layer.

Every table and storage object has policies that check the calling user's `profiles.status`. Even a hostile script with the publishable key can't bypass these because RLS is enforced by Postgres itself.

This means the same security model holds whether the caller is the legitimate website, a script someone wrote, or a curl from the command line. Worth verifying with an unauthenticated test:

```bash
curl https://<your-project>.supabase.co/rest/v1/gallery_items \
  -H "apikey: <publishable-key>"
# → returns [] because RLS blocks reads without an approved profile
```

### 3. Separation of identity and authorization

`auth.users` is managed entirely by Supabase Auth (the user identity, password, email confirmation flow). The application doesn't touch it directly.

`public.profiles` is the project's own table, joined 1:1 with `auth.users`. It holds the *authorization* signal — the `status` column — that gates everything else.

The trigger `on_auth_user_created` ties them together: every new auth user gets a matching profile with `status='pending'` automatically. This decoupling means you can never have a "user without a profile" or a "profile without a user" state — and it makes the admin approval flow clean (admin only edits `profiles`, never `auth.users`).

### 4. Soft delete by default

`gallery_items` has `deleted_at` and `deleted_by` columns. The user-facing "delete" action sets these via an UPDATE rather than performing a DELETE. RLS hides soft-deleted rows from approved users; admins can still see them.

**Why:** family memorial photos are exactly the kind of content where an accidental delete would be devastating. The cost is essentially nothing — a couple of columns and one extra clause in the SELECT policy.

Hard delete is reserved for the admin via the Supabase dashboard, when you actually want to free storage.

### 5. Pre-upload image processing

Phone photos coming straight out of a camera have two problems for a family site:

1. **They embed GPS coordinates** (and the user's name, device model, timestamp). Stripping this on upload is a privacy win.
2. **They're huge** (5–10 MB for a 12 MP shot). Uncompressed, a few thousand photos blow past the 1 GB free-tier cap.

`gallery/assets/image-process.js` runs both fixes client-side:

- The image is loaded into a `<canvas>` element — this re-encodes the bitmap and naturally drops EXIF metadata
- If the longest edge exceeds 2000px, the image is scaled down preserving aspect ratio
- Output is a JPEG (or PNG if the original was PNG) at quality 0.88

Original files never leave the device. Family members don't have to think about it.

---

## Data model

### Profile lifecycle

```
            sign up + email confirmed
                       ▼
                   ┌──────────┐
                   │ pending  │ ◄── cannot read or write gallery
                   └────┬─────┘
                        │ admin approves
                        ▼
                   ┌──────────┐
                   │ approved │ ◄── normal family member
                   └────┬─────┘
                        │
                        │ admin sets to disabled  ◄────┐
                        ▼                               │
                   ┌──────────┐                         │
                   │ disabled │ ──── admin re-approves ─┘
                   └──────────┘
                   
                   ┌──────────┐
                   │  admin   │ ◄── the project owner; bootstrap via 04_seed_admin.sql
                   └──────────┘
```

The `status` column is the single source of truth for what a user can do. RLS policies and storage policies all read it via the `public.is_approved(uid)` / `public.is_admin(uid)` helper functions.

### Gallery item lifecycle

```
   upload → row in gallery_items + file in storage at <user>/<uuid>.<ext>
              │
              │ owner edits (own rows only)
              ▼
   uploaded ──┴── soft delete (deleted_at set) ──── admin restore (clear deleted_at)
                       │
                       │ admin hard-deletes (file + row)
                       ▼
                  permanently gone
```

---

## Why these specific Supabase features

| Feature | What we use it for | Why not a custom solution |
|---|---|---|
| Auth | Email + password + email confirmation | Password hashing, salting, reset emails are easy to get wrong |
| RLS | The authorization lock | Database-enforced means no frontend bug can leak data |
| Storage | File uploads | Built-in signed URLs and per-folder ACL via `(storage.foldername(name))[1] = auth.uid()::text` |
| Triggers | Auto-create profile on signup | Keeps `auth.users` and `profiles` in sync without an application-level race |
| Postgres functions | `keepalive()`, `is_approved()`, `is_admin()` | Server-side logic, callable from the client via RPC, runs in the same transaction as queries |

If we ever outgrow Supabase, every one of these maps cleanly to standard Postgres + S3-compatible storage. The lock-in is minimal.

---

## Frontend module structure

```
gallery/assets/
├── supabase-client.js   ← creates the singleton SDK client; exports CATEGORIES
├── auth.js              ← signUp, signIn, signOut, getProfile, requireApproved
├── image-process.js     ← processImage(File) → Blob with EXIF stripped + resized
├── gallery.js           ← listItems, uploadItem, softDelete, updateItem, getSignedUrl
└── styles.css           ← shared design tokens; reuses memorial site's color/font system
```

Each gallery HTML page (`login.html`, `pending.html`, `index.html`) imports only what it needs from these modules and contains its own page-specific event handling inline. There's no framework or build step — ES modules are loaded directly by the browser from CDN (`@supabase/supabase-js` via jsdelivr).

This keeps the project debuggable (just open DevTools and read the source), reduces deploy complexity (just static files), and makes it easy to onboard a future maintainer who isn't familiar with whatever framework happened to be trendy when this was built.

---

## Memorial site internals

`index.html` is a single self-contained file deliberately. The contents:

- Inline CSS using CSS custom properties for design tokens (`--green`, `--gold`, `--surface`, etc.) — these are reused by the gallery's `styles.css`
- Six content sections (Biography, Publications, Public Service, Legacy, Life Beyond, Fields of Work) plus Hero, Sources, and footer
- A small JS block at the bottom handling:
  - Mobile nav drawer (open/close, outside-click, Escape key)
  - `IntersectionObserver` for scroll-spy active links
  - English ↔ Nepali language toggle with `localStorage` persistence
  - i18n string dictionary covering nav, headings, tributes, and footer

No external dependencies, no images beyond the hero portrait, no analytics, no tracking. Loads instantly on any connection.

---

## Keep-alive workflow

Lives in [`.github/workflows/keepalive.yml`](../.github/workflows/keepalive.yml). Two failure modes it has to guard against:

1. **Supabase 7-day inactivity pause** — solved by calling `public.keepalive()` daily, which does an UPDATE on a tracker table (any DB write counts as activity).
2. **GitHub disabling scheduled workflows after 60 days of repo inactivity** — solved by occasional commits to the repo. If you ever notice scheduled workflows haven't run in weeks, push any commit to re-arm.

The workflow inlines the Supabase URL and publishable key directly (rather than using GitHub Secrets) because those values are already in the committed JS bundle. Adding a Secrets layer would be cargo-culted, not actually more secure.

The function returns `"pong"` as a string. The workflow's curl checks for that exact output and fails loudly if it gets anything else — so a silent breakage in the function definition shows up as a red X in the Actions UI rather than silently letting the project pause.

---

## What's deliberately NOT in this project

Worth listing, so future-maintainer-you doesn't waste time adding these:

- **Build step / bundler** — pure ES modules; the only "build" is `git push`
- **Framework (React, Vue, etc.)** — overkill for a few HTML pages
- **State management library** — gallery state lives in the DB; UI state is per-page
- **Service worker / PWA** — the site is fast enough already; offline use is not a goal
- **Comments / reactions on gallery items** — out of scope for v1, easy to add via a new table later
- **Per-item permissions beyond "approved or not"** — everyone in the family sees everything; no need for per-album ACLs
- **Custom admin UI** — Supabase dashboard handles approval cleanly enough; one-off admin tasks don't justify the maintenance cost
- **Automated photo backups** — relying on Supabase's durability for now; will revisit if the family accumulates irreplaceable content

---

## Future-work bookmarks

Things that have come up in discussion but were deliberately deferred:

- **Email-on-signup notification to admin** — Supabase Edge Function + Resend, fires on `auth.users` insert
- **Custom admin page** at `/gallery/admin.html` — list pending users with approve buttons; phone-friendly
- **Move storage to Cloudflare R2** — 10 GB free, no egress fees; requires swapping the storage client
- **Custom domain** (e.g. `drchaitanyasubba.org`) — $10/year at Cloudflare Registrar
- **Automated backups** — weekly script that exports DB to SQL + photos to a secondary bucket
- **Server-side image variants** — Supabase's image transformation API can generate thumbnails on the fly

Each of these is a small, well-scoped addition that can be done in an afternoon if/when there's demand.
