PR Title: Make Alembic migrations idempotent and add env example

Summary:
- Make migration e4a593... idempotent by inspecting DB catalog before dropping/creating indexes and foreign keys. This prevents Postgres transaction aborts when running migrations on DBs that are partially migrated.
- Add and normalize `backend/.env.example` and update docs to recommend copying it to `backend/.env` and not committing real secrets.
- Update `docs/offline_sync_roadmap.md` to mention local Postgres dev setup and `.env` handling.

Files changed:
- backend/alembic/versions/e4a593920909_postgresql_single_source_of_truth_sync_.py (guard index/constraint ops)
- backend/.env (cleaned duplicate sqlite entry)   # note: this file should remain uncommitted
- backend/.env.example (placeholder values; default password changed to placeholder)
- docs/offline_sync_roadmap.md (updated progress and next steps; added client CI job plan)
- flutter_app/mobile/lib/data/local/database_helper.dart (added `sync_meta` table helpers)
- flutter_app/mobile/lib/data/remote/postgres_api_service.dart (added `fetchChangesSinceSeq`)
- flutter_app/mobile/lib/data/sync/postgres_sync_service.dart (added `pullChangesSinceSeq` implementation)
- flutter_app/mobile/test/unit/postgres_sync_pull_test.dart (unit test for pull behavior)
- flutter_app/mobile/test/data/sync/postgres_sync_push_test.dart (new unit test for batch push id_map behavior)
- flutter_app/mobile/test/test_helpers.dart (centralized test bootstrap: sqflite ffi init, fake secure storage)
- .github/workflows/flutter-unit-tests.yml (added: Flutter unit test job for mobile)
- Many mobile tests updated to use shared `test/test_helpers.dart` to ensure deterministic FFI initialization and plugin mocks in CI (see commit for a full list of modified tests).

Testing:
- Ran `alembic upgrade head` against local Postgres (DATABASE_URL from `backend/.env`) successfully.
- Ran `pytest backend/tests/test_migrations.py::test_alembic_upgrade_head_against_postgres -q` (passed).
- Ran full backend test suite against local Postgres: `pytest -q` → All tests passed (33 passed, 0 failed).
- Client: Added unit tests for `pullChangesSinceSeq` and ran them locally after adding test bootstrap helpers. Local Flutter unit tests for the modified mobile tests pass (sqflite ffi init and fake plugin mocks used).
- CI: Added `.github/workflows/flutter-unit-tests.yml` to run mobile unit tests on PRs and pushes to `feat/sync-replay-migrations` and `main` (will validate once branch is pushed and CI runs).

Notes for reviewers:
- Confirm the guarded index/constraint logic is acceptable for migration strategy. It intentionally avoids failing on missing indexes/constraints to make re-runs safe. This is preferable in deployed environments where schema may have been partially migrated.
- Ensure CI runs migrations in a fresh DB and as part of the upgrade path, but the guarded checks will reduce flakiness for re-runs on existing DBs.

Follow-ups / Next steps:
- Push the local branch `feat/sync-replay-migrations` and open a PR (currently blocked by a transient DNS/network issue when attempting `git push`).
  - Exact commands I will run once network is available:
    - `git push --set-upstream origin feat/sync-replay-migrations`
    - Create PR via GitHub UI or `gh pr create --fill` (if `gh` CLI is configured).
- Add a small integration test in CI that runs `alembic upgrade head` twice to validate idempotency (optional).
- Create an automated migration smoke test for real Postgres in the CI pipeline.

---

If you'd like, I can open the PR for you once the branch is pushed (I will need permission to push to your repo), or I can provide the exact git commands and PR text for you to run locally.