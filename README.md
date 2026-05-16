# Dr. Chaitanya Subba — Tribute Site & Family Gallery

A two-part project in memory of Dr. Chaitanya Subba (1946–2022):

1. **Public memorial site** — a single-page tribute covering his biography, scholarship, public service, and legacy.
2. **Private family gallery** — a password-protected, admin-approved space where family members can upload and share photos, scans, and documents.

**Live site:** https://shreyashparajuli.github.io/dr-chaitanya-subba-portfolio/

---

## What's where

```
.
├── index.html                     # Memorial site (single page, fully static)
├── Baba.jpg                       # Portrait shown in the hero section
│
├── gallery/                       # Family gallery (private, auth-gated)
│   ├── login.html                 # Sign in / request access
│   ├── pending.html               # "Awaiting approval" screen
│   ├── index.html                 # Gallery grid + upload modal
│   └── assets/
│       ├── supabase-client.js     # Supabase SDK init + public credentials
│       ├── auth.js                # Session, profile, route guard
│       ├── gallery.js             # Upload, list, soft-delete
│       ├── image-process.js       # EXIF strip + resize on upload
│       └── styles.css             # Shared design tokens with memorial site
│
├── supabase/                      # Database schema, policies, helpers
│   ├── README.md                  # Detailed setup walkthrough
│   ├── 01_schema.sql              # Tables, trigger, indexes
│   ├── 02_rls.sql                 # Row-Level Security policies
│   ├── 03_storage.sql             # Storage bucket + policies
│   ├── 04_seed_admin.sql          # Bootstrap the first admin
│   └── 05_keepalive.sql           # Keep-alive function (anti-pause)
│
├── .github/workflows/
│   └── keepalive.yml              # Daily ping to prevent Supabase pause
│
└── docs/
    ├── SETUP.md                   # Fresh install from scratch
    ├── OPERATIONS.md              # Day-to-day admin tasks
    └── ARCHITECTURE.md            # How the system fits together
```

---

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| **Hosting (static)** | GitHub Pages | Free, zero-config, fits a single-file memorial perfectly |
| **Hosting (gallery frontend)** | GitHub Pages (same repo) | Pure HTML/JS/CSS — no build step required |
| **Backend** | Supabase | Postgres + Auth + Storage + Row-Level Security in one place |
| **Auth** | Supabase Auth (email + password) | Standard, secure, with built-in email confirmation |
| **Authorization** | Postgres Row-Level Security (RLS) | Hard lock on every read/write at the database layer |
| **File storage** | Supabase Storage (private bucket) | Signed URLs; same security gate as the database |
| **Email** | Gmail SMTP via App Password | Free, reliable, no third-party signup |
| **Keep-alive** | GitHub Actions cron | Free for public repos; prevents 7-day inactivity pause |

---

## How the memorial site works

`index.html` is a single self-contained file: HTML structure, inline CSS using design tokens, and a small inline JS block that handles:

- Mobile navigation drawer
- Smooth scroll between sections
- Scroll-spy active-link highlighting
- English ↔ Nepali language toggle (persisted in `localStorage`)

The page has seven sections:

1. **Hero** — portrait, name, years, tagline
2. **Biography** — narrative + life timeline + academic credentials
3. **Publications** — six entries from 1991 to 2025 (including the posthumous LAHURNIP study he led)
4. **Public Service & Policy** — AJDC/NFDIN, NPC, Constituent Assemblies, DAPAN, IIDS/JEP, UNDP HDR
5. **Legacy & Tributes** — three tribute quotes plus six legacy cards
6. **Life Beyond Scholarship** — politics, sport, personal life
7. **Fields of Work** — six expertise tiles
8. **Sources & Further Reading** — links to external profiles and obituaries

---

## How the family gallery works

A high-level walk-through:

1. **Visitor** opens `/gallery/login.html` → enters email + password under "Request access" → Supabase creates an auth user → a Postgres trigger creates a matching row in `public.profiles` with `status = 'pending'`.
2. **Visitor** receives an email confirmation (via Gmail SMTP) → clicks the link → confirmed.
3. **Admin (you)** opens Supabase → Table Editor → `profiles` → flips the new user's `status` to `approved`.
4. **Family member** logs back in → route guard reads `profiles.status` → no longer pending → gallery loads.
5. They can browse, filter by category, upload (photos auto-resize and have EXIF metadata stripped before upload), or soft-delete their own items.

The whole feature is enforced by Row-Level Security policies on three tables and the storage bucket. Even if someone obtained the publishable Supabase key, RLS prevents them from reading or writing gallery data without an approved profile.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full technical breakdown.

---

## Getting started

### If you're cloning this fresh (new Supabase project)

See the step-by-step walkthrough: [docs/SETUP.md](docs/SETUP.md).

In short:

1. Create a new Supabase project.
2. Paste the project URL + publishable key into `gallery/assets/supabase-client.js`.
3. Run the five SQL files in `supabase/` in order.
4. Configure Auth (Site URL, SMTP, email confirmation).
5. Bootstrap yourself as admin via `04_seed_admin.sql`.
6. Push to GitHub; GitHub Pages takes care of serving.

### If you just want to run the existing project locally

```bash
# From the repo root
python -m http.server 8000
```

Then open `http://127.0.0.1:8000/` for the memorial site, or `http://127.0.0.1:8000/gallery/login.html` for the gallery.

(ES modules in the gallery require a real HTTP server — opening files directly with `file://` will not work.)

---

## Day-to-day operations

Most-common tasks are covered in [docs/OPERATIONS.md](docs/OPERATIONS.md):

- **Approving a new family member** (3 clicks in Supabase)
- **Recovering a soft-deleted photo** (toggle one column)
- **Disabling someone's access**
- **Editing or replacing memorial content**
- **Reading current usage / storage**
- **Restoring a paused Supabase project**

---

## Costs & limits

**Memorial site:** essentially free forever — GitHub Pages limits are far beyond what a tribute site needs.

**Gallery backend:** Supabase free tier covers a family-scale gallery for years. Realistic projections:

| Family upload pace | Photos/month | Free tier runway |
|---|---|---|
| Light (a few per holiday) | ~10 | 8–10 years |
| Moderate | ~50 | 4–5 years |
| Active | ~200 | 14–16 months |

The only recurring cost worth considering is an optional **custom domain (~$10/year)** if you'd rather use `drchaitanyasubba.org` than the `github.io` URL.

Hard limits:
- File storage: 1 GB (after auto-resize, ≈ 2,000–5,000 photos)
- Bandwidth: 5 GB/month
- Database: 500 MB (effectively unreachable — metadata is tiny)
- The 7-day inactivity pause is handled automatically by the keep-alive workflow (see below)

---

## Keep-alive (anti-pause)

Free Supabase projects pause after 7 days of database inactivity. To prevent this:

- `supabase/05_keepalive.sql` defines `public.keepalive()` — a small RPC that updates a single-row tracker table.
- `.github/workflows/keepalive.yml` calls that RPC once per day (04:17 UTC) via GitHub Actions.
- A successful run updates `keepalive_log.last_ping` and increments `ping_count`.

If the workflow ever fails to run for an extended period (e.g. the repo goes 60+ days without any commit, which disables scheduled workflows), the project will pause after 7 days of no activity. The pause is non-destructive: all data is preserved, and one click in the Supabase dashboard restores the project in ~1 minute.

To verify it's working:

```sql
select last_ping, ping_count from public.keepalive_log;
```

`last_ping` should be from the last 24 hours.

---

## Security model — short version

Three layers, in order of trust:

1. **Route guard (UX, soft):** the client-side `requireApproved()` function in `auth.js` redirects unauthenticated or pending users away from gallery pages. This is purely for user experience.
2. **JWT (medium):** Supabase sessions are JWT-based and short-lived (auto-refreshed). The auth user ID is bound to every database request.
3. **Row-Level Security (hard, the real lock):** every table and storage object has policies that check `profiles.status` for the calling user. Even with the public Supabase URL and publishable key, no one can read or write gallery data without an approved profile.

The publishable key is intentionally committed to the repo — Supabase's security model treats it as public. The corresponding **service role key is never committed and is never in client code.** That separation is the entire point of RLS.

---

## Backup & recovery

Currently the project relies on Supabase's own data durability (paused projects retain data for ~90 days before potential cleanup; active projects are continuously backed up server-side by Supabase).

For truly irreplaceable photos, an additional periodic backup strategy is worth setting up — see "future work" in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Sources & further reading

External references that informed the memorial content:

- *दलित, सीमान्तकृतका अनन्य मित्र स्वर्गीय डा. चैतन्य सुब्बा* — Hira Vishwakarma, Online Khabar (May 2022)
- *जो नाम मात्रका सुब्बा थिएनन्, किपटिया सुब्बा पनि थिए* — Kumar Yatra Tamang, Indigenous Voice
- *The Relevance of Indicators in Monitoring the Progress of Indigenous Peoples Toward Achieving Sustainable Development Goals* — LAHURNIP (May 2025), led by Dr. Chaitanya Subba

These are linked from the live memorial site's "Sources & Further Reading" section.

---

## License & use

This is a personal tribute project. The code may be reused as a template; the biographical content, photographs, and tributes are kept with the family and should not be reproduced elsewhere without permission.
