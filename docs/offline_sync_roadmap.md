# Offline-first Sync Roadmap

**Status:** Draft

## 🎯 Goals
- Keep local SQLite (Flutter) and backend PostgreSQL synced reliably for offline-first use.
- Maintain production performance (fast local reads/writes) while ensuring eventual consistency with Postgres.
- Provide deterministic conflict resolution and operational monitoring.

---

## 🔧 High-level architecture (recommended)
- Backend: PostgreSQL (single source of truth) + sync endpoints and a change-log table (append-only) or logical decoding stream.
- Mobile (Flutter): SQLite (use Drift/SQLCipher if encryption needed) as local DB with a small sync engine that: records local changes, queues them, and pushes/pulls deltas to/from the server.
- Transport: REST for bulk sync + WebSocket or Server-Sent Events for near-real-time updates (optional).
- IDs: Use UUIDv4 for cross-device unique IDs; store per-entity `last_modified` timestamp and `version` (monotonic integer or vector clock if needed).

---

## 🧩 Core components
1. Change tracking
   - Server: `changes` table recording (entity_type, entity_id, operation, payload, timestamp, origin_client_id, server_seq).
   - Client: local change queue (ops with client_seq, timestamp).

2. Sync protocol (Push / Pull)
   - Push: client sends a batch of local changes to `/api/sync/push` with `since` (last server_seq or timestamp). Server validates & applies in a transaction; server returns results and conflicts.
   - Pull: client requests changes from server `/api/sync/pull?since=<server_seq>` to receive batches of server-side changes it hasn't seen.
   - Checkpointing: client stores last successful server_seq and last push token.

3. Conflict handling
   - Prefer deterministic strategies: LWW (last-write-wins) using authoritative `server_time` or field-level merge rules for complex types.
   - For critical entities (e.g., inventory counts), use server-calculated merges and return a `conflict` response for client review where automatic resolution is unsafe.

4. Consistency guarantees
   - Eventual consistency for most reads.
   - For operations requiring strong correctness (e.g., decrement stock on sale), prefer server-side transactional endpoints and optimistic locking.

---

## ✅ Implementation roadmap (milestones)
1. Design (1 week)
   - Audit existing backend models (`src/models.py`) and Flutter schemas (`lib/`), identify entities requiring sync (products, sales, stores, users, etc.).
   - Decide change-log approach: in-DB `changes` table vs. logical replication.

2. API & Data model (1–2 weeks)
   - Add `changes` table and migration scripts (alembic) for Postgres.
   - Implement endpoints: `POST /api/sync/push`, `GET /api/sync/pull`, `GET /api/sync/status`, optional `ws://` for pushes.
   - Create tests validating ordering, idempotency, and conflict responses.

3. Server prototype (2–3 weeks)
   - Implement change-apply logic with transactional guarantees and conflict detection.
   - Add admin tooling for replays and backfilling.

4. Flutter client prototype (2–3 weeks)
   - Add local change queue and robust retry/backoff (use WorkManager / background tasks plugins for background sync).
   - Integrate with Drift (formerly moor) for typed DB access and streamables.
   - Implement push/pull flow, checkpoint persistence, and conflict resolution flow.

5. End-to-end tests & QA (1–2 weeks)
   - Simulate offline cases, forks, double-inserts, and reconciliation.
   - Add integration tests (local emulator + test Postgres) and CI jobs.

6. Rollout & monitoring (1 week)
   - Feature-flag rollout, monitoring for sync lag, error rates, and conflict rates.
   - Telemetry on last_sync_time, queue_depth, failures.

---

## 🗂 Phases & checklists
Use the checklist below to track progress; check boxes indicate completed items.

- [x] **Phase 0 — Audit (done)**
  - [x] Inventory backend models and sync-relevant fields (products, sales, inventory, stores, users)
  - [x] Inventory Flutter sync components and background tasks (`lib/sync/`, `Workmanager`, `sqflite` usage)
  - Acceptance: list of files and entities captured in repo audit

- [x] **Phase 1 — Design & Spec (completed)**
  - [x] Draft change-log schema + alembic migration
  - [x] Define sync API: push/pull endpoints, payload shape, status codes, idempotency
  - [x] Decide conflict resolution policies and acceptance criteria per entity
  - Estimated: 1 week
  - Acceptance: migration + API spec + unit tests for ordering and idempotency

- [x] **Phase 2 — Server prototype (completed)**
  - [x] Implement `changes` table + `server_seq` incrementation and indexing (migration added)
  - [x] Update `/api/sync/changes` to accept `since_seq` and return ordered changes (router updated)
  - [x] Implement idempotent `/api/sync/push` with temp-id mapping (prototype applied, tests added)
  - [x] Add admin tooling for replays and backfills (API + CLI implemented, tests added)
  - [x] Integration tests for push/pull roundtrip and conflict handling (backend)
  - [x] Replay tooling: idempotent replay, create-skip, dry-run and CLI output tested
  - [x] Alembic migration hardening: guarded index/constraint ops for idempotency
  - Estimated: 2–3 weeks (server prototype completed)
  - Acceptance: integration tests demonstrating push/pull roundtrip, replay behavior, and migration idempotency
  - **Notes:** All server-side tests pass locally; migrations are idempotent and the repo includes a CI workflow to validate repeated `alembic upgrade head` and a replay dry-run smoke test.

---

## 🧪 CI & migration idempotency checks (new)
- Add a CI workflow that validates Alembic migrations are safe to re-run:
  - Run `alembic upgrade head` twice against a fresh Postgres service and assert both succeed (no transaction aborts / schema errors).
  - Run `pytest` to ensure migrations + app logic operate correctly after repeated upgrades.
  - Run the `backend/scripts/replay_changes.py --from <min_seq> --to <max_seq> --dry-run` as a smoke-test of replay tooling.
- This helps catch migration regressions and prevents flaky upgrade behavior in CI and production.


---

## 🔄 Progress update (2025-12-30)
- **Completed:** Design, Change model, Alembic migration, `/api` sync router updates, **server-side prototype tests for push/pull**, admin replay tooling, and **client pull integration (partial)**. Alembic issues were fixed to be cross-dialect (SQLite dev and PostgreSQL prod).
- **Current focus:** Stabilize Flutter unit/widget tests and CI, finalize client-side test coverage, and push the feature branch / open a PR (the local branch was committed but a previous `git push` failed due to a transient network/DNS issue). A GitHub Actions job for mobile unit tests (`.github/workflows/flutter-unit-tests.yml`) and a shared test bootstrap (`test/test_helpers.dart`) were added to the repo to help stabilize CI runs.
- **Next:** Re-run `git push` to publish the branch and open a PR (include the `PR_DRAFT.md` contents), expand client tests to cover push workflows and conflict resolution, and update remaining tests to use the centralized test helpers so CI runs deterministically.

- **Recently completed:** Server prototype work now includes integration tests for push/pull, replay CLI and API with dry-run, and migration idempotency hardening. Backend tests pass locally and against local Postgres; a CI workflow has been added to validate migration idempotency and run replay smoke tests. On the client side, `sync_meta` persistence, `PostgresApiService.fetchChangesSinceSeq(...)`, `PostgresSyncService.pullChangesSinceSeq()` and unit tests for pull behavior were implemented and are passing locally after test-harness fixes (sqflite ffi init, secure-storage mocking, JSON typing fixes).

---

## 🧪 Local Postgres dev setup (new)
- **Status:** I found a `.env` file at `backend/.env` that contains a Postgres `DATABASE_URL`. I removed a duplicate sqlite line and fixed a stray trailing dot; if you prefer a different URL or credentials, update `backend/.env` (do NOT commit secrets).

- **Example `.env` entry** (do NOT commit credentials):

  DATABASE_URL=postgresql://postgres:postgres@localhost:5432/pos_dev

- **Note:** Consider adding a `.env.example` with placeholders to the repo and adding `backend/.env` to `.gitignore` so real secrets aren't accidentally committed.
- **Quick start (local Postgres)**
  1. Ensure `DATABASE_URL` is set in your environment or in a local `.env` file.
  2. From the `backend/` directory run:
     - `alembic upgrade head`  # apply migrations to your local Postgres
  3. To validate migrations run the integration migration test (requires `DATABASE_URL` pointing to Postgres):
     - `pytest backend/tests/test_migrations.py::test_alembic_upgrade_head_against_postgres -q`
  4. Run the full backend test suite against Postgres by exporting `DATABASE_URL` and running `pytest -q`.

- **Notes & recommendations**
  - The codebase already supports reading `DATABASE_URL` from environment (see `alembic/env.py` and `backend/entrypoint.sh`).
  - Migrations were hardened to be idempotent (guarded index/constraint ops) so they can be re-run safely on DBs that already contain parts of the schema.
  - Prefer not to store secrets in committed files. If you want, I can create a local `.env` for you, or load a provided `.env` file temporarily to run the commands — tell me which you prefer.

---

> Notes: Backend tests are green; Flutter widget tests currently show 4 failing tests (missing `AuthProvider` in test harness and a network mocking issue). I'm working on triaging those now and will update this document as each subtask completes.

- [ ] **Phase 3 — Client prototype (in-progress)**
  - [x] Add local checkpoint persistence (e.g., `sync_meta` table) and helpers to store `last_server_seq`
  - [x] Implement `fetchChangesSinceSeq(...)` and `pullChangesSinceSeq()` to apply server change-log and commit `head_seq` atomically (unit tests added)
  - [ ] Local change queue + per-change `client_seq` and checkpointing for outgoing pushes
  - [ ] Background worker integration (Workmanager) with batching and retry/backoff
  - [ ] UI for conflict handling, sync errors, and status
  - [ ] Optional: switch to Drift for typed local DB if needed
  - Estimated: 2–3 weeks (partial progress)
  - Acceptance: e2e test showing offline sale recorded locally and synced to server; push flow and conflict handling validated in tests and CI
  - **Notes / immediate next steps:** Stabilize Flutter tests in CI (sqflite FFI + plugin mocks), add integration tests for push/push-pull roundtrip, and push branch + open PR.

- [ ] **Phase 4 — E2E tests & QA**
  - [ ] Simulate offline cases, forks, double-inserts, retries, and reconciliation
  - [ ] CI jobs for integration tests and metrics collection

- [ ] **Phase 5 — Rollout & monitoring**
  - [ ] Feature-flag rollout and staged deployments
  - [ ] Instrument metrics (server_seq head, per-client lag, queue depth, conflict rate) and dashboards
  - [ ] Runbook for recovery and replay

- [ ] **Phase 6 — Docs & training**
  - [ ] Update `docs/` with runbook, troubleshooting, and developer guide
  - [ ] Share release notes and training for operations and support teams

---

> How to use: mark the checklist boxes as you complete each item. I'll keep this roadmap updated as we make progress and open PRs for each phase.

---

## ⚠️ Risks & mitigations
- Duplicate writes / id collisions: use UUIDs and idempotency keys.
- Conflicts on frequently updated numeric counters (e.g., stock): use server-side aggregation and optimistic locking or implement operational transforms for counters.
- Large payloads: use batching and compression; prune/compact change-log older than a retention window or snapshot checkpoints.

---

## 🔒 Security
- Use scoped auth tokens; verify `origin_client_id` and client permissions.
- Encrypt payloads over TLS; optionally encrypt local DB (SQLCipher).

---

## 📋 Operational notes
- Backfill plan: run a one-time migration to populate `changes` for existing state or generate periodic snapshots for new clients.
- Monitoring: expose metrics for `server_seq` head, per-client lag, conflict rate, and sync error rates.

---

## 📎 Next steps (short-term)
1. Push local branch (`feat/sync-replay-migrations`) and open a PR using `PR_DRAFT.md` (or I can open the PR for you once the remote is reachable).
2. Add a Flutter CI job that initializes `sqflite_common_ffi` and provides plugin mocks (notably `flutter_secure_storage`) so client unit tests run deterministically in CI.
3. Stabilize and expand client tests: add push-path tests, conflict scenarios, and an end-to-end push/pull roundtrip test (mock server or test Postgres instance).
4. Harden test bootstrap: move `sqflite_common_ffi` init and plugin mock registration into a shared test helper to avoid duplication across tests.
5. Once tests and CI are green, draft the PR description, link the CI runs, and request a review for merge and staged rollout.

---

**References & patterns:** offline-first, event sourcing, change-data-capture (CDC), CRDTs (when field-level merging is required).


> Add this document to the roadmap backlog and I can proceed to identify the exact files to change in this repository and start a prototype PR.
