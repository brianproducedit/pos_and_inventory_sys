# Portfolio Refactor Roadmap

**Project:** POS & Inventory System  
**Repo:** [github.com/brianproducedit/pos_and_inventory_sys](https://github.com/brianproducedit/pos_and_inventory_sys)  
**Created:** 22 August 2026  
**Purpose:** Turn this working product into a clean, job-application showcase (one `main` branch, GitHub Releases with APK, recruiter-friendly README, no secrets, no dead files, **no paid cloud required to demonstrate**).

**How to use this file:** Check a box when that item is actually done. Check a **phase** only after every sub-item in it is done. Do phases in order unless a note says they can overlap.

---

## What this project is

A **multi-store Point of Sale and inventory** product for small retailers.

| Layer | Stack | Role |
| --- | --- | --- |
| Mobile app | Flutter (Android-first), Provider + Drift/SQLite | Cashiers sell, managers stock, admins run stores — **offline-first** |
| Backend | FastAPI, SQLAlchemy, Alembic, PostgreSQL | Auth (JWT), RBAC, REST APIs, change-log sync |
| Local data | Drift tables with `clientId` / `serverId` / `syncStatus` | UI reads/writes local DB only; sync runs in the background |
| Ops (target) | Local Drift seed + optional Docker Compose | **No Railway / no paid host.** APK and clone-and-run both work offline. |

**Product capabilities already in the codebase**

- Roles: `superadmin`, `admin`, `cashier`
- Multi-store assignment, store switching, products/SKU/stock
- POS cart, sales, sequential receipts, sales history
- Offline login (after first online login), queued sync, conflict UI
- Analytics dashboards, audit logs
- Bluetooth thermal printing, PDF/share
- Settings, user/admin/cashier management, data-protection hooks
- Zimbabwe-oriented defaults (Africa/Harare timezone; Paynow stub on the backend)

**What a recruiter should take away**

> “I built an offline-first Flutter POS that writes to local SQLite, syncs to a FastAPI/Postgres backend, and handles real retail constraints: roles, stores, receipts, and printers.”

That story is already true. The repo currently hides it behind empty READMEs, stale branches, Railway debug commits, committed secrets, and a demo path that **fails without a paid hosted API**.

### Demonstration contract (non-negotiable)

A reviewer must be able to do **all** of the following **without Railway, Render, Heroku, or any credit card**:

1. **Sideload the GitHub Release APK** → log in with documented demo users → sell items, browse inventory, see analytics. Data comes from **on-device mock/seed** (Drift), not the internet.
2. **Clone the repo** → `docker compose up` (optional, free, local) → Flutter against `localhost` / `10.0.2.2` to show **real sync**. Docker Desktop is free for this use; Postgres image is free.
3. **Never** hit `*.up.railway.app` from committed config, tests, or the release APK.

If the backend is unreachable, the app must **not** look broken. It must enter **Demo / local-only mode** (banner on home/POS) and keep working.

---

## Current-state findings (do not skip)

Treat these as facts the later phases exist to fix.

### Git / GitHub

- [x] **Default remote branch is `main`**, but it is **stale**. `origin/main` is ~70 commits **behind** `origin/master` and has a unique “Initial commit” that is not on `master`.
- [x] **All real work lives on `master`** (local `HEAD` = `origin/master` = `48117a4`).
- [x] Feature branches are already contained in `master` (0 unique commits):
  - local `feature/v2-offline-first`
  - local + remote `refactor/drift-migration-roadmap`
  - remote `origin/feat/sync-offline`
- [x] GitHub CLI (`gh`) is **not installed** on this machine; Releases/branch deletes will need `gh` or the GitHub UI.
- [x] Uncommitted work exists on `master` (offline sync fixes in mobile repos, `app_database`, `auth_service`, `sync_service`, plus `docs/OFFLINE_SYNC_FIXES_ROADMAP.md`). Finish or stash this **before** branch surgery.

### Security (blocking for a public portfolio)

- [x] **Live credentials are in git history and files**, including `docs/RAILWAY_DEPLOYMENT_ROADMAP.md` (`SECRET_KEY`, `DEFAULT_SUPERADMIN_PASSWORD=bk007bang`).
- [x] The same password appears in ad-hoc scripts (`backend/test_product_sync.py`, `flutter_app/mobile/test_api_connection.dart`, others).
- [x] Generated `flutter_app/mobile/lib/config/env.g.dart` hardcodes `https://backend-production-5388.up.railway.app`.
- [x] CORS is `allow_origins=["*"]` in `backend/src/main.py`.

If this repo is or will be public: **rotate Railway (and any reused) secrets immediately**, even before code cleanup. Removing a file from `HEAD` does not remove it from git history.

### Dead / confusing surface area

- [x] Root `README.md` is three duplicate titles and nothing else.
- [x] `flutter_app/desktop` is the default Flutter **counter** app, unused.
- [x] `flutter_app/shared` is leftover SQLite models / old sync — not used by the V2 Drift app.
- [x] `SyncDemoScreen` (`lib/ui/sync_demo.dart`) is a developer harness, not a product screen.
- [x] Backend root has many one-off `test_*.py` / `test_railway_*.py` scripts aimed at the live Railway URL (not pytest).
- [x] `docs/` is ~30 files of day-by-day sprint notes, completed roadmaps, and Railway deploy logs. Recruiters will not read them; they make the project look unfinished.

### CI / Releases

- [x] **Seven** workflows, overlapping and partly broken:
  - `ci.yml` — useful (backend pytest + Flutter analyze/test), but only triggers on `main`
  - `flutter-ci.yml` / `flutter_ci.yml` — `flutter pub get` at **repo root** (will fail; app is in `flutter_app/mobile`)
  - `flutter-unit-tests.yml` — stale branch name, `--no-sound-null-safety`
  - `integration.yml` — same root-path problem
  - `migrations-idempotency.yml` — duplicates backend tests
  - `pr-ci-failure-reporter.yml` — extra noise for a solo portfolio repo
- [x] No GitHub Release, no APK upload workflow. `docs/APK_INSTALLATION_GUIDE.md` still says `YOUR_USERNAME`.
- [x] Android `applicationId` is `com.pos.inventory`; release signing is already wired to `key.properties` (good — do **not** commit the keystore).

### Architecture debt (showcase-relevant, not all must be finished)

- Dual state management: **Provider** is the real app; **Riverpod** is imported in `main.dart` with little use.
- V1 leftovers: `product_service.dart` and similar still exist beside `*_repository_v2.dart`.
- Startup still seeds/overwrites superadmin password from env (`init_db.py`) — fine for Docker demo if documented; dangerous if pointed at production.
- Offline sync Issue 3 (sales / receipt numbers) is **in progress** in uncommitted files.

---

## Target end state (what “done” looks like)

1. **One branch:** GitHub default `main` contains today’s `master` history (or a cleaned rewrite if you purge secrets from history). No `master`, no leftover feature branches.
2. **No secrets** in tree or, if rewritten, in history. Railway URLs and passwords gone. `.env.example` files only.
3. **APK is self-contained:** first launch seeds mock stores/products/users/sales into Drift. Login works with `demo` / `demo123` (or similar) **with airplane mode on**.
4. **Optional local backend:** `docker compose up` + Flutter `--dart-define=DEMO_MODE=false` shows live sync. Zero paid platforms.
5. **GitHub Releases:** tagged `v1.0.0` with a **release APK** (demo mode). APKs are **not** committed to git.
6. **One README** that sells the product, architecture, and how to run it. `docs/` keeps only evergreen technical docs.
7. **One CI workflow** green on `main` plus one **release** workflow.
8. Desktop scaffold, shared leftover, Railway scripts, V1 duplicates, debug certs, and sprint diaries are gone.

**Product shape:** mobile app + FastAPI + Postgres + Docker Compose **as optional**. Default reviewer path is **APK or Flutter run in demo mode**. Railway is retired, not replaced with another PaaS.

---

## Guiding rules

1. **Do not commit APKs, keystores, `.env`, or `key.properties`.**
2. **Rotate leaked secrets before advertising the repo.**
3. **Finish or revert uncommitted sync work before merging branches.**
4. **Prefer deleting completed process docs over archiving them in-repo.**
5. **Force-push only on `main` after a backup tag**, and only to replace the stale initial commit (Phase 2). Do not force-push after the repo is public and others have cloned it unless you are doing a planned history rewrite (Phase 1.3).
6. **Default branch name is `main`** (GitHub already uses it). Stop using `master` after Phase 2.
7. **No paid platforms in the demo path.** Do not add Railway, Render, Fly, AWS, etc. as a README requirement. Mock/seed data is the correct fallback.
8. **Delete unused files; do not comment them out or move them to `old/`.**

---

## Phase 0 — Pre-flight (this machine and this working tree)

**Goal:** Nothing is lost when you start deleting branches and files.

- [x] **0.1** Install GitHub CLI and authenticate  
  - [ ] `winget install GitHub.cli` (or installer from github.com/cli/cli)  
  - [ ] `gh auth login`  
  - [ ] Confirm: `gh repo view brianproducedit/pos_and_inventory_sys`

- [x] **0.2** Snapshot the current work  
  - [ ] `git tag backup/pre-portfolio-refactor` on current `master`  
  - [ ] `git push origin backup/pre-portfolio-refactor`  
  - [ ] Optional zip of the repo folder off-git (APKs, keystore, `.env` if they exist only locally)

- [x] **0.3** Decide fate of **uncommitted** mobile/sync changes  
  - [ ] Read `docs/OFFLINE_SYNC_FIXES_ROADMAP.md` vs the diffs in `sale_repository_v2.dart`, `sync_repository.dart`, `app_database.dart`, `auth_service.dart`, `sync_service.dart`, `main.dart`  
  - [ ] Either: commit them on `master` as `fix: offline sync and login` **or** stash and revisit in Phase 7  
  - [ ] Do **not** start Phase 2 with a dirty working tree

- [x] **0.4** Confirm repo visibility  
  - [ ] If **public** (or about to be): start Phase 1.1 (rotate secrets) **today**  
  - [ ] If **private** until polish: still rotate; assume it will be public for applications

**Phase 0 complete:** [x]

---

## Phase 1 — Secret hygiene (do before any “clean public README”)

**Goal:** A recruiter cloning the repo cannot log into your production backend or reuse your JWT secret.

### 1.1 Rotate everything that leaked

- [x] **1.1.1** Retire Railway (preferred) or rotate if you keep it privately  
  - [ ] **Delete the Railway project/service** so this portfolio does not depend on a paid host  
  - [ ] Change `SECRET_KEY` and `DEFAULT_SUPERADMIN_PASSWORD` if the service still exists for 24h  
  - [ ] Change any user passwords that matched `bk007bang`

- [x] **1.1.2** Search the tree for leftovers (after edits, search again)  
  - [ ] `bk007bang`  
  - [ ] `SWiPZ7LS` / JWT-looking strings  
  - [ ] `up.railway.app`  
  - [ ] `backend-production-5388`  
  - [ ] Personal proxy IPs in `flutter_app/mobile/README.md` (`192.168.49.1`, `10.236.39.195`)

### 1.2 Remove secrets and production URLs from the tree

- [x] **1.2.1** Delete or rewrite `docs/RAILWAY_DEPLOYMENT_ROADMAP.md` (do not keep the password/key even “for history”)
- [x] **1.2.2** Strip credentials from ad-hoc tests; point them at env vars or delete the scripts (Phase 3)
- [x] **1.2.3** Stop committing generated env:  
  - [ ] Add `flutter_app/mobile/lib/config/env.g.dart` to `.gitignore` **or** generate it with a **localhost** default and `obfuscate: true`  
  - [ ] Add `flutter_app/mobile/.env.example` with `BASE_URL=http://10.0.2.2:8000` (Android emulator → host) and `http://localhost:8000` for desktop/web  
  - [ ] Document `--dart-define=BASE_URL=...` as the release override
- [x] **1.2.4** Add `backend/.env.example` (`DATABASE_URL`, `SECRET_KEY`, `DEFAULT_SUPERADMIN_*`) with **placeholders only**
- [x] **1.2.5** Tighten `.gitignore`: `.env`, `*.jks`, `key.properties`, `*.apk`, `*.aab`, `keystore/`

### 1.3 Git history (choose one)

Pick **A** if the repo is already public or you have shared the URL. Pick **B** only if you are comfortable rewriting history and force-pushing.

- [x] **Option A (minimum):** rotate or **delete Railway** (1.1) + remove from current tree (1.2). Old commits may still contain the password; they must be useless because the service is gone.
- [ ] **Option B (stronger):** `git filter-repo` (or BFG) to purge `RAILWAY_DEPLOYMENT_ROADMAP.md` and files that embed passwords, then force-push `main`. Re-add a **redacted** setup doc. Notify: anyone with an old clone must re-clone.

**Phase 1 complete:** [x]

---

## Phase 2 — One `main` branch (GitHub cleanup)

**Goal:** GitHub shows a single default branch with the real codebase. Extra branches are gone.

**Facts to use**

- GitHub default is already `main`.
- Real code is `origin/master`.
- `main` and `master` are **divergent** (`main` has an extra initial commit; `master` has ~70 unique commits). A normal merge may create a messy “unrelated histories” merge. Prefer **make `main` identical to current `master`**.

### 2.1 Update `main` to match `master`

- [x] **2.1.1** Working tree clean; backup tag pushed (Phase 0.2)
- [x] **2.1.2** Local: `git checkout master` then `git branch -f main master` (or `git checkout -B main master`)
- [x] **2.1.3** Push: `git push origin main --force`  
  - Justification: `origin/main` is a leftover initial commit, not a protected production history you care about.  
  - If GitHub branch protection blocks this, disable protection on `main` temporarily.
- [x] **2.1.4** Confirm GitHub default branch is `main` (Settings → General → Default branch)
- [x] **2.1.5** Confirm `main` tip equals former `master` tip (`48117a4` or whatever commit you tagged)

### 2.2 Delete extra branches

Delete **remote first**, then local.

- [x] **2.2.1** `git push origin --delete master`
- [x] **2.2.2** `git push origin --delete feat/sync-offline` (if it exists)
- [x] **2.2.3** `git push origin --delete refactor/drift-migration-roadmap`
- [x] **2.2.4** In GitHub UI, delete any other remote branches (open PRs first: close or merge)
- [x] **2.2.5** Local: `git branch -D master` after you are on `main`
- [x] **2.2.6** Local: `git branch -D feature/v2-offline-first`
- [x] **2.2.7** Local: `git branch -D refactor/drift-migration-roadmap`
- [x] **2.2.8** `git remote prune origin` and confirm `git branch -a` shows only `main` (+ `origin/main`)

### 2.3 Point tools at `main` only

- [x] **2.3.1** CI `on.push.branches` / `pull_request.branches` → `main` only (done for real in Phase 6)
- [x] **2.3.2** Any docs that say “merge to master” → `main`

**Phase 2 complete:** [x]

---

## Phase 3 — Purge unused, deprecated, and one-off files

**Goal:** Opening the repo shows one product. No counter-app, no Railway scratch scripts, no V1 duplicates, no personal proxy certs. **Delete files; do not keep an `archive/` folder in git.**

After each sub-phase: `rg` the tree for the deleted names and for `railway`, `bk007bang`, `heroku`. `flutter analyze` / `pytest` must still run.

### 3.1 Unused Flutter projects

- [x] **3.1.1** Delete entire `flutter_app/desktop/` (default Flutter counter app)
- [x] **3.1.2** Delete entire `flutter_app/shared/` (pre-Drift SQLite models / old sync)
- [x] **3.1.3** Grep and remove references: `package:desktop`, `package:shared`, `flutter_app/desktop`, `flutter_app/shared`

### 3.2 Railway / live-URL scratch scripts (not pytest)

Keep: `docker-compose.yml`, `backend/Dockerfile`, `backend/entrypoint.sh`, `backend/tests/`, `backend/alembic/`, `backend/src/`, `backend/scripts/replay_changes.py` (if tests use it), `backend/scripts/prune_sqlite.py` only if still needed for **local** seed (otherwise delete in 3.3).

Delete:

- [x] **3.2.1** `backend/test_railway_backend.py`
- [x] **3.2.2** `backend/test_railway_comprehensive.py`
- [x] **3.2.3** `backend/test_railway_detailed.py`
- [x] **3.2.4** `backend/test_product_sync.py`
- [x] **3.2.5** `backend/test_store_sync.py`
- [x] **3.2.6** `backend/test_audit_api_remote.py`
- [x] **3.2.7** Remaining `backend/test_*.py` at **backend root** (pytest lives in `backend/tests/`): `test_api.py`, `test_auth.py`, `test_me.py`, `test_stores.py`, `test_sync_endpoint.py`, `test_make_change.py`, `test_hard_delete_endpoint.py`, `test_audit_api.py`, `test_audit_structure.py`, `test_local_audit.py`, `test_store_switch_flow.py`
- [x] **3.2.8** Repo-root `test_audit_structure.py`, `test_sync_endpoint.py`, `test_sync_flow.md`
- [x] **3.2.9** Flutter one-offs: `flutter_app/mobile/test_api_connection.dart`, `test_sync_push.dart`, `test_sync_push_simple.dart`
- [x] **3.2.10** Replace any remaining hardcoded `up.railway.app` with env / demo mode (Phase 5). Confirm no `railway.json` / `nixpacks.toml` / `Procfile`.

### 3.3 Backend inspect / check / cleanup one-offs

These are REPL scripts against a live DB, not product:

- [x] **3.3.1** `backend/check_stores.py`, `check_all_products.py`, `check_changes_table.py`, `check_sync_queue.py`, `check_product_sales.py`
- [x] **3.3.2** `backend/inspect_db.py`, `inspect_products.py`, `inspect_audit_logs.py`, `inspect_stores.py`
- [x] **3.3.3** `backend/cleanup_inactive_stores.py`
- [x] **3.3.4** `backend/scripts/debug_product_create.py`, `debug_analytics.py`, `debug_create_admin.py`
- [x] **3.3.5** Decide: keep **one** `backend/scripts/seed_demo.py` (written in Phase 5) and delete the rest of ad-hoc seeders

### 3.4 Deprecated app code and developer-only UI

- [x] **3.4.1** Inventory `lib/` for unused V1: `product_service.dart`, unused `*_service.dart` if repositories replaced them; delete if `rg` shows no production imports
- [x] **3.4.2** Delete or stop routing `lib/ui/sync_demo.dart` (`SyncDemoScreen`) — not a product screen
- [x] **3.4.3** Delete or hide `theme_preview_screen.dart` unless used in the settings UI
- [x] **3.4.4** Remove `Sync Demo` / “Seed DB” drawer items except behind `kDebugMode` **or** replace with the official Demo mode toggle (Phase 5)
- [x] **3.4.5** Delete `flutter_app/mobile/android/proxy-ca.cer` and `proxy-ca-browser.cer` (personal proxy; not for recruiters)
- [x] **3.4.6** Strip personal proxy `setx HTTP_PROXY` notes from `flutter_app/mobile/README.md` / `ENVIRONMENT_SETUP.md`

### 3.5 Duplicate / junk docs and env templates (files, not the rewrite in Phase 4)

- [x] **3.5.1** Delete `flutter_app/mobile/ENVIRONMENT_SETUP.md` if it duplicates root/docs setup
- [x] **3.5.2** Delete placeholder READMEs inside `lib/data/repositories`, `lib/domain`, `lib/data/utilities` if they only say “files to add”
- [x] **3.5.3** Delete generated junk from git if present: `*.iml`, local `.env`, built APKs

### 3.6 Backend defaults after Railway is gone

- [x] **3.6.1** CORS: `CORS_ORIGINS` env; examples use localhost, not `*`
- [x] **3.6.2** Remove leftover **debug** store/schema dump endpoints from the Railway 500-debug commits; keep `/health`
- [x] **3.6.3** Superadmin password only from env / `.env.example` placeholders (`changeme`), never a real password

### 3.7 Verification

- [x] **3.7.1** `rg -i railway` returns only this roadmap (until Phase 4/9) or a one-line “not used” note
- [x] **3.7.2** `cd backend && pytest -q` still collects `tests/`
- [x] **3.7.3** `cd flutter_app/mobile && flutter analyze` has no missing-file errors from deletions

**Phase 3 complete:** [x]

---

## Phase 4 — Documentation diet

**Goal:** `docs/` is a small set of evergreen files. Sprint archaeology is gone.

### 4.1 Delete completed / superseded docs

Safe to delete once Phase 1.2 has removed secrets from any file you are not deleting:

- [x] **4.1.1** Day logs: `DAY_1_IMPLEMENTATION_SUMMARY.md` … `DAY_5_IMPLEMENTATION_SUMMARY.md`
- [x] **4.1.2** Phase logs: `PHASE_3.6_PROGRESS.md`, `PHASE_3.6_UI_MIGRATION_GUIDE.md`, `PHASE_7_COMPLETION_SUMMARY.md`
- [x] **4.1.3** Completed migration reports: `V2_MIGRATION_COMPLETION_REPORT.md`, `V2_OFFLINE_FIRST_AUDIT_REPORT.md`, `V2_REMEDIATION_ROADMAP.md`, `V2_OFFLINE_FIRST_ROADMAP.md` (replace with a short architecture section in README + one doc in 4.2)
- [x] **4.1.4** `DRIFT_MIGRATION_ROADMAP.md`, `TEST_CLEANUP_SUMMARY.md`, `flutter_app/mobile/docs/ui_integration_roadmap.md`
- [x] **4.1.5** `RAILWAY_DEPLOYMENT_ROADMAP.md` (after secret rotation)
- [x] **4.1.6** Root `test_sync_flow.md` if redundant with `docs/sync_runbook.md`

**Keep this roadmap** (`PORTFOLIO_REFACTOR_ROADMAP.md`) until all phases are checked, then either keep it as project history or delete it in Phase 9.

### 4.2 Keep / rewrite a small evergreen set

- [x] **4.2.1** `docs/ARCHITECTURE.md` — one diagram: UI → Drift → sync queue → FastAPI → Postgres; roles; offline rules. Fold in the useful bits of `OFFLINE_FIRST_IMPLEMENTATION.md`, `client_sync_design.md`, `developer_guide_offline_first.md`.
- [x] **4.2.2** `docs/LOCAL_SETUP.md` — (1) APK demo mode, (2) optional Compose + Flutter. No Railway.
- [x] **4.2.3** `docs/API.md` — point to `/docs` (OpenAPI) + short notes from `sync_api_spec.md`
- [x] **4.2.4** `docs/APK_INSTALLATION_GUIDE.md` — rewrite with the **real** Releases URL: `https://github.com/brianproducedit/pos_and_inventory_sys/releases`
- [x] **4.2.5** Optional keep: `docs/user_guide_offline_usage.md`, `docs/support_faq.md`, `docs/backup_recovery_procedures.md` (trim; no internal passwords)
- [x] **4.2.6** Optional keep: `docs/PERFORMANCE_OPTIMIZATION.md`, `docs/DATABASE_LOCK_PREVENTION.md` if still accurate
- [x] **4.2.7** Delete `flutter_app/mobile/README.md` Flutter-template + proxy notes; replace with 10 lines pointing to root README
- [x] **4.2.8** Rewrite `backend/README.md` to point at root README + `docs/LOCAL_SETUP.md` (remove stray `flutter pub run` / “Next steps” junk)

**Phase 4 complete:** [x]

---

## Phase 5 — Zero-cost demonstration (mock / seed data; no paid host)

**Goal:** The APK and `flutter run` are a complete POS demo **with the radio off**. Docker Compose is an **optional** second path to show sync. **Do not** put a public Railway URL in the app. Mock data is the intended solution, not a shortcut.

The app already stores users, stores, products, and sales in Drift and can log in offline **after** a first online login. Recruiter phones never did that first login. Fix: **seed Drift on first launch** and treat the API as optional.

### 5.1 Demo mode flag

- [x] **5.1.1** Add a single switch, e.g. `--dart-define=DEMO_MODE=true` (default **true** for release APK) and `false` only when a reviewer runs Compose
- [x] **5.1.2** When `DEMO_MODE=true`: skip live `BASE_URL`; do not call Railway or any host; disable background `Workmanager` sync or no-op it
- [x] **5.1.3** Persistent banner: `Demo — local data, sync off` on home and POS (so it is honest in interviews)
- [ ] **5.1.4** Settings: “Local demo” vs “Connect to server” (server = user-typed `http://10.0.2.2:8000` or LAN IP). Connecting is opt-in, never a baked PaaS URL
- [x] **5.1.5** If `DEMO_MODE=false` and the API is down: fall back to local data + banner, **do not** freeze on login errors

### 5.2 First-launch seed (Flutter / Drift)

Create `lib/data/demo/demo_seed.dart` (name flexible). Idempotent: only seed if `users` (or a `demo_seeded` pref) is empty.

- [x] **5.2.1** Users (password hashes the app’s offline auth already understands):  
  - `demo` / `demo123` — **cashier**  
  - `admin` / `demo123` — **admin**  
  - `superadmin` / `demo123` — **superadmin**  
  - Mark `isLocalOnly = true`; never use production passwords
- [x] **5.2.2** Stores: e.g. “Harare CBD” and “Avondale”
- [x] **5.2.3** Products: 8–15 SKUs with prices and stock (beverages, snacks, airtime-style items — enough for a live POS demo)
- [x] **5.2.4** Sales + sale items: 10–20 past sales across a few days so **analytics and sales history** are not empty
- [x] **5.2.5** Receipt / transaction numbers increment from a sensible start (no `sale# null`)
- [ ] **5.2.6** Optional: one inventory log / audit row so those screens are not blank
- [ ] **5.2.7** Unit test: empty DB → seed → expected user and product counts; second run does not duplicate

### 5.3 Login and POS without a network

- [x] **5.3.1** Login screen copy: demo credentials visible in debug/demo builds (or a “Fill demo cashier” button)
- [x] **5.3.2** `OfflineAuthService.login`: if demo user exists locally, **do not require** connectivity; skip `loginOnline` in demo mode
- [ ] **5.3.3** Store picker works from seeded stores
- [ ] **5.3.4** Full cashier loop: add to cart → checkout → receipt → stock decrements → sale in history
- [ ] **5.3.5** Admin loop: add/edit product, see it on POS
- [ ] **5.3.6** Analytics charts render from seeded + new sales
- [ ] **5.3.7** Airplane mode: cold start → login → sale still works

### 5.4 Optional local backend (free; not required for APK)

- [ ] **5.4.1** `docker compose up --build` → Postgres + API on `:8000`; `GET /health` ok
- [ ] **5.4.2** Alembic + superadmin from `.env.example` (`changeme`)
- [x] **5.4.3** `backend/scripts/seed_demo.py` loads the **same** catalog as the Flutter seed (stores/products) so sync demos match
- [ ] **5.4.4** Compose healthcheck on backend (`curl /health`)
- [ ] **5.4.5** Document emulator URL `http://10.0.2.2:8000` and physical-device LAN IP
- [ ] **5.4.6** `flutter analyze` / `flutter test` never need a running server or Railway

### 5.5 Sync story when Compose is used

- [ ] **5.5.1** With `DEMO_MODE=false` and local API: online login caches credentials; offline login still works
- [ ] **5.5.2** Create product / sale on device → appears in Postgres (manual test; can wait for Phase 7 fixes)
- [ ] **5.5.3** Demo-mode APK must **not** enqueue failing sync to a dead host (empty queue or sync disabled)

### 5.6 What not to do

- [x] **5.6.1** Do not add a free-tier Railway/Render “for the portfolio”
- [x] **5.6.2** Do not commit a production `BASE_URL`
- [x] **5.6.3** Do not ship an empty-database APK that only works after “talk to my server”

**Phase 5 complete:** [ ]

---

## Phase 6 — CI: one test workflow, one release workflow

**Goal:** Green checks on `main`. APKs appear only on GitHub Releases.

### 6.1 Delete duplicate / broken workflows

- [ ] **6.1.1** Delete `.github/workflows/flutter-ci.yml`
- [ ] **6.1.2** Delete `.github/workflows/flutter_ci.yml`
- [ ] **6.1.3** Delete `.github/workflows/flutter-unit-tests.yml`
- [ ] **6.1.4** Delete `.github/workflows/integration.yml` (or merge a **working** `working-directory: flutter_app/mobile` job into `ci.yml` later)
- [ ] **6.1.5** Delete `.github/workflows/migrations-idempotency.yml` **or** fold “alembic upgrade twice” into `ci.yml` as one step
- [ ] **6.1.6** Delete `.github/workflows/pr-ci-failure-reporter.yml`

### 6.2 Single `ci.yml`

- [ ] **6.2.1** Triggers: `push` and `pull_request` on `main`
- [ ] **6.2.2** Job `backend`: Postgres service, `pip install`, `pytest`, `alembic upgrade head`
- [ ] **6.2.3** Job `mobile`: `working-directory: flutter_app/mobile`, `flutter pub get`, `dart run build_runner build` if `env.g.dart` is generated in CI, `flutter analyze`, `flutter test`
- [ ] **6.2.4** Pin a Flutter version (not floating `stable` without a version) so CI does not randomly break
- [ ] **6.2.5** Push a trivial commit and confirm both jobs pass on GitHub

### 6.3 Release workflow (APK → GitHub Releases)

Do **not** put APK binaries in the git tree.

- [ ] **6.3.1** Add `.github/workflows/release.yml`  
  - Trigger: `push` of tags `v*.*.*` (and optionally `workflow_dispatch`)  
  - Checkout, setup Java + Flutter  
  - `flutter build apk --release --dart-define=DEMO_MODE=true` in `flutter_app/mobile`  
  - Upload `app-release.apk` with `softprops/action-gh-release` (or `gh release create`)
- [ ] **6.3.2** Signing  
  - [ ] Generate a dedicated **upload** keystore locally; store `KEYSTORE_BASE64`, `KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD` as GitHub Actions secrets  
  - [ ] Decode keystore in the workflow; write `key.properties` at build time  
  - [ ] Confirm `key.properties` and `.jks` stay gitignored
- [ ] **6.3.3** Versioning: bump `version:` in `flutter_app/mobile/pubspec.yaml` (`1.0.0+1` → match tag `v1.0.0` and build number)
- [ ] **6.3.4** Release notes template: Android min version, unknown sources, **demo credentials**, “no internet required”, optional Docker sync
- [ ] **6.3.5** Dry-run: `git tag v1.0.0 && git push origin v1.0.0` after Phase 8 polish (or a `v0.1.0` smoke tag first)

**Phase 6 complete:** [ ]

---

## Phase 7 — Code cleanup that shows up in interviews

**Goal:** Opening `lib/` does not look like two generations of the same app. Sync is honest.

### 7.1 Finish or clearly scope offline sync

- [ ] **7.1.1** Close remaining items in `OFFLINE_SYNC_FIXES_ROADMAP.md` (sales online/offline detection, receipt numbers not `sale# null`, push sales)
- [ ] **7.1.2** Manual test matrix:  
  - [ ] Online login → offline reopen  
  - [ ] Create product offline → reconnect → appears on server  
  - [ ] Complete sale offline → reconnect → sale + stock on server  
  - [ ] Receipt number increments locally even offline
- [ ] **7.1.3** When done, delete `docs/OFFLINE_SYNC_FIXES_ROADMAP.md` or mark it historical

### 7.2 Collapse V1 / V2 naming

- [ ] **7.2.1** If V1 repositories/services are unused, delete them (`product_service.dart` if dead, old providers)
- [ ] **7.2.2** Rename `*_v2.dart` → canonical names **or** leave V2 names but document “V2 is the app” in ARCHITECTURE.md (renames are nicer; do in one PR)
- [ ] **7.2.3** Pick **Provider** as the app standard; remove unused Riverpod `ProviderScope` if it does nothing

### 7.3 Noise reduction

- [ ] **7.3.1** Strip emoji `debugPrint` spam from repository create/update paths (or wrap in `kDebugMode` and shorten)
- [ ] **7.3.2** Remove `backend/scripts/debug_*.py` or move to a `scripts/dev/` folder mentioned as optional
- [ ] **7.3.3** `Paynow` — either document as “planned / stub” or hide from README until it works end-to-end

### 7.4 Tests that match the story

- [ ] **7.4.1** Keep backend pytest suite green after deleting ad-hoc scripts
- [ ] **7.4.2** Keep a small Flutter unit set: auth offline, repository enqueue, sync status mapping
- [ ] **7.4.3** Skip flaky E2E in CI until paths/working-directory are fixed (document in README)

**Phase 7 complete:** [ ]

---

## Phase 8 — First public APK on GitHub Releases

**Goal:** Releases has an installable APK that **demonstrates the POS with no server**. README links to it.

- [ ] **8.1** Phase 5 demo seed + `DEMO_MODE=true` is the **release default**. No Railway URL in `env.g.dart`.
- [ ] **8.2** APK mode is **fixed** for v1: self-contained local demo (mock/seed Drift). Optional “connect to local server” is documented for developers only, not required for the download.
- [ ] **8.3** Release notes state: demo logins, airplane-mode OK, sync requires local Docker (optional)
- [ ] **8.4** `pubspec.yaml` version matches tag
- [ ] **8.5** Run release workflow (Phase 6.3); confirm `app-release.apk` on the Release (built with `DEMO_MODE=true`)
- [ ] **8.6** Sideload on a phone **with Wi‑Fi off**: login `demo` / `demo123` → one sale → inventory and analytics update
- [ ] **8.7** Update `docs/APK_INSTALLATION_GUIDE.md` (real Releases URL, version, size, demo credentials, unknown-sources steps)
- [ ] **8.8** Repeat for `v1.0.1` only when you have a real fix

**Phase 8 complete:** [ ]

---

## Phase 9 — Comprehensive GitHub README (the actual showcase)

**Goal:** The repo landing page is the interview. Write this **after** the tree is cleaned so screenshots and commands are true.

Create/replace root `README.md` with these sections (check each when written and verified):

- [ ] **9.1** Title + one-paragraph pitch (offline-first POS for multi-store retail)
- [ ] **9.2** Badges: CI, license, last release
- [ ] **9.3** Screenshots (login, POS, inventory, analytics, sync indicator) — 4–6 images in `docs/screenshots/`
- [ ] **9.4** Features list (roles, offline, sync, printing, analytics)
- [ ] **9.5** Architecture (mermaid or PNG): Flutter ↔ Drift ↔ Sync ↔ FastAPI ↔ Postgres
- [ ] **9.6** Tech stack table
- [ ] **9.7** Repository layout (what each top-level folder is)
- [ ] **9.8** Quick start **A (APK):** download Release, demo login, no backend  
- [ ] **9.8b** Quick start **B (developers):** Docker Compose + Flutter `DEMO_MODE=false` + `BASE_URL=http://10.0.2.2:8000`  
- [ ] **9.9** Demo credentials (`demo` / `demo123`, plus admin/superadmin) — local/demo only
- [ ] **9.10** Android APK: link to [Releases](https://github.com/brianproducedit/pos_and_inventory_sys/releases)
- [ ] **9.11** API: `http://localhost:8000/docs`
- [ ] **9.12** Testing: how to run backend pytest and Flutter tests
- [ ] **9.13** Security note: no production secrets in repo; rotate if you fork
- [ ] **9.14** Roadmap / known limitations (honest: desktop app not shipped, Paynow stub, iOS not the focus)
- [ ] **9.15** License (`MIT` is typical for portfolio unless you have a reason not to)
- [ ] **9.16** Author: name, LinkedIn, email — **this is the CTA**

GitHub extra (Settings):

- [ ] **9.17** Repo description: `Offline-first Flutter POS + FastAPI/Postgres inventory system`
- [ ] **9.18** Topics: `flutter`, `fastapi`, `postgresql`, `offline-first`, `pos`, `drift`, `dart`, `python`
- [ ] **9.19** Homepage: Releases URL or empty
- [ ] **9.20** Pin this repo on your GitHub profile

**Phase 9 complete:** [ ]

---

## Phase 10 — Interview polish (optional but high ROI)

- [ ] **10.1** 60-second loom/GIF: airplane mode → login `demo` → cart → checkout → receipt → analytics (proves no Railway)
- [ ] **10.2** One page in README: “Design decisions” (why local-first, why `clientId`/`serverId`, why FastAPI)
- [ ] **10.3** CONTRIBUTING.md only if you want issues; otherwise skip (solo portfolio)
- [ ] **10.4** After this roadmap is fully checked, delete `docs/PORTFOLIO_REFACTOR_ROADMAP.md` **or** leave it as “project log” — your choice
- [ ] **10.5** Final pass: `git log --oneline -20` looks coherent; no “Trigger Railway redeploy” as the first thing people see (that is already buried; a squash is **not** required)

**Phase 10 complete:** [ ]

---

## Suggested execution order (calendar)

This is one person, part-time. Adjust, but do not reorder 1 before 2 if the repo is public.

| When | What |
| --- | --- |
| Day 1 | Phase 0 + Phase 1.1 rotate secrets. Commit uncommitted sync work or stash. |
| Day 1–2 | Phase 1.2 file cleanup. Phase 2 force-update `main`, delete other branches. |
| Day 2–3 | Phase 3 purge unused/deprecated files. Phase 4 delete sprint docs. |
| Day 3–5 | **Phase 5 mock/seed demo mode** (this unblocks APK). Phase 6 CI green. |
| Day 5–6 | Phase 7 sync/sales + leftover V1 deletion. |
| Day 6–7 | Phase 6.3 + Phase 8 Release APK **in demo mode**. |
| Day 7–8 | Phase 9 README + screenshots. Phase 10 GIF. |

---

## Out of scope (do not let these block the showcase)

- Google Play / App Store listing
- A real desktop POS (the current desktop folder is not that)
- Perfect test coverage / rewriting all `*_v2` names in the same week as Releases
- Kubernetes, Terraform, or a new cloud just for the resume
- **Any paid host (Railway, Render, Fly.io, AWS) as a demo dependency**
- Rewriting FastAPI in another language

---

## Progress log

| Phase | Status | Date completed | Notes |
| --- | --- | --- | --- |
| 0 Pre-flight | Done | | |
| 1 Secrets | Done | | Rotate before public |
| 2 One `main` | Not started | | Force-push `main` = old `master` |
| 3 File purge | Done | | Desktop, shared, Railway scripts, V1 |
| 4 Docs diet | Done | | |
| 5 Mock/demo (no PaaS) | In Progress | | Seed Drift; APK works offline |
| 6 CI + release workflow | Not started | | |
| 7 Code polish | Not started | | Includes uncommitted sync |
| 8 APK on Releases | Not started | | `DEMO_MODE=true` |
| 9 README | Not started | | After the tree is true |
| 10 Interview extras | Not started | | |

**Entire roadmap complete:** [ ]
