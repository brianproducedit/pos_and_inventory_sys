# Roadmap: Maximize Offline Functionality & Secure Defaults ✅

This checklist outlines the phased plan to: secure credentials in environment files, ensure a default `superadmin` exists in every install, migrate to PostgreSQL, clean SQLite leaving only the default `superadmin`, and improve offline-first reliability and performance for both backend and Flutter client.

> Note: Each item below includes implementation notes and acceptance criteria. I'll check items off as I complete them.

---

## Phase 1 — Audit (in-progress) 🔍
- [x] Scan codebase for hard-coded credentials, DB config, and seeding scripts
  - Notes: Located `init_db.py` (seeds `superadmin`), `src/database.py` (reads `DATABASE_URL` with SQLite fallback), Alembic supports `DATABASE_URL` env override.
  - Acceptance: Inventory of code locations created.

## Phase 2 — Secrets & Configs (.env) 🔐
- [x] Add `.env.example` with placeholders and recommended values (do NOT commit real secrets)
  - Recommended entries: `DATABASE_URL`, `DEFAULT_SUPERADMIN_USERNAME`, `DEFAULT_SUPERADMIN_PASSWORD`, `TEST_SUPERADMIN_PASSWORD`
- [x] Add `.env` to `.gitignore` and add a short README section describing how to populate `.env` for dev, test, and production
- Acceptance: No literal secret values remain in tracked code; running app after populating `.env` yields expected behavior.
  - Note: `backend/.env.example` already contains the recommended keys and `.env` is excluded in root `.gitignore`.

## Phase 3 — Ensure default superadmin exists and is safe ✅
- [x] Move default credentials out of code into env config or generate securely at first-run
  - Implementation chosen: `init_db.py` now reads `DEFAULT_SUPERADMIN_PASSWORD` from env; if not provided a secure temporary password is generated and printed. Seeding remains idempotent and `must_change_password=True` is enforced.
  - Acceptance: `init_db.py` creates or updates `superadmin` and repository no longer contains literal default passwords in code.

## Phase 4 — Postgres Integration & Migrations 🐘
- [x] Ensure `DATABASE_URL` can point to PostgreSQL and document required env vars
- [x] Update `alembic.ini` and `alembic/env.py` to prefer `DATABASE_URL` from environment (already supported, verify in CI and Dockerfiles)
- [x] Create migration and test migration workflows for Postgres (CI runs Alembic and integration migration test added)
- Acceptance: App can run using Postgres by setting `DATABASE_URL` and migrations apply successfully.

## Phase 5 — Clean SQLite for Offline (local device) 🧹
- [x] Provide a lightweight script to sanitize a device-local SQLite DB, retaining only the default `superadmin` user (with `must_change_password=True`) and removing sensitive production artifacts
  - Implementation: `scripts/prune_sqlite.py` creates a pruned sqlite DB (or replaces existing DB with `--replace`) and seeds the `superadmin` from env.
- [x] Optionally, provide a CLI command like `posctl prune-sqlite --keep-superadmin` or similar (added `scripts/posctl.py`)
- Acceptance: Running the cleanup results in a minimal DB with only essential tables and the `superadmin` user and no secrets.

## Phase 6 — Offline-first & Sync Strategy ⚡️
- [x] Design an offline-first sync strategy (choices: occasional background sync with server API, push/pull with conflict resolution, use of CRDTs for complex merges)
- [x] Implement local queuing of writes, retry/backoff, and conflict resolution policy (server-side scaffolding implemented; client-side queue TBD)
- [x] Expose a sync endpoint and versioned API for incremental device sync (initial product-only endpoints added: `/api/sync/changes`, `/api/sync/push`)
- [x] Extend server-side sync to `stores` and `users` (create/update/delete + basic conflict reporting)
- [ ] Implement full client-side sync (Flutter) and extend to all resources (IN-PROGRESS: Flutter client sync demo using Drift started)
- [x] Implement deterministic conflict handling (LWW) with superadmin `force` option and `suggestion` metadata in conflict responses

### Phase 6b — Flutter client sync work
- [x] Scaffold Flutter demo: add Drift DB schema, sync service, and minimal UI (`flutter_app/mobile/lib/db`, `sync`, `ui/sync_demo.dart`) ✅
- [x] Add WorkManager dependency and initial background dispatcher (`sync/sync_background.dart`) — **in-progress**
- [ ] Complete background sync scheduling, backoff, and persistence (WorkManager / background_fetch)
- [in-progress] Implement conflict merge UI and admin force flow (scaffold added; UI + force action in progress)
- [partial] Add integration tests for offline CRUD, queue persistence, and conflict handling (conflict + push/pull e2e added)
- Acceptance: App remains fully usable offline (CRUD operations locally), and sync resumes without data loss when network becomes available.

### Phase 6b — Conflict helpers & client work (short-term)
- [ ] Add conflict-resolution helper endpoint (server-side) to return authoritative server suggestions for a set of conflicts
- [ ] Add client merge UI/UX spec and admin 'force' workflow
- [ ] Implement full Flutter client sync demo (Drift + background queue + background worker) — **next priority**

### Immediate next tasks (what I'll implement now)
- [x] Add `flutter_app/mobile/.env.example` entries and guidance (done)
- [x] Replace hard-coded fallback for `superadmin` with env-first approach and secure generation (done)
- [x] Add simple unit tests for background dispatcher `sync/sync_background.dart` (done)
- [ ] Implement WorkManager periodic registration and manifest changes (in-progress)
- [x] Add integration tests for sync flows (`test/e2e/sync_e2e_test.dart`) — **done**
- [x] Push branch `feat/sync-offline` and create PR (https://github.com/brianproducedit/pos_and_inventory_sys/pull/new/feat/sync-offline) — **done**
- [x] Add CI job to run E2E (bring up backend container + run `flutter test`) — **done**
- [x] Add PR CI failure reporter workflow (comments on PRs when CI fails) — **done**
- [ ] Plan Postgres migration CI job (planned)




## Phase 7 — Performance & Reliability 🔧
- [ ] Profile slow endpoints and optimize queries, add necessary indexes
- [ ] Add DB connection pooling and robust error handling for transient failures
- [ ] Harden tests: add unit and integration tests for the seeded `superadmin`, DB switching, and offline sync flows
- Acceptance: All tests pass; key endpoints show measurable improvement.

## Phase 8 — Docker/Deployment & CI 📦
- [ ] Update Dockerfile(s) and `docker-compose.yml` to support both `postgres` (for production) and `sqlite` (for local/offline)
- [ ] Ensure environment variables are injected via secrets or environment in production CI/CD, not in code
- Acceptance: Images start with either DB backend by changing `DATABASE_URL`.

## Phase 9 — Docs & Finalization 🧾
- [ ] Update `README.md`, add `ENVIRONMENT_SETUP.md` section with steps to prepare `.env`, initialize DB, and run cleanup for offline installs
- [ ] Mark completed checklist items and create a changelog entry for the migration
- Acceptance: Documentation explains how to install app for offline use and how to migrate to Postgres.

---

If you'd like, I can now:
1. Create `.env.example` and add `.env` to `.gitignore` (recommended immediate next step) ✅
2. Replace the hard-coded `bk007bang` fallback in `init_db.py` to prefer env or generation, and add a safe seeding routine (I can implement either approach you prefer).
3. Add a `scripts/prune_sqlite.py` to produce a minimal sqlite DB with only `superadmin`.

Tell me which of those you'd like me to start on first, or I can proceed with an implementation plan for all of them.
