PR Title: Make Alembic migrations idempotent and add env example

Summary:
- Make migration e4a593... idempotent by inspecting DB catalog before dropping/creating indexes and foreign keys. This prevents Postgres transaction aborts when running migrations on DBs that are partially migrated.
- Add and normalize `backend/.env.example` and update docs to recommend copying it to `backend/.env` and not committing real secrets.
- Update `docs/offline_sync_roadmap.md` to mention local Postgres dev setup and `.env` handling.

Files changed:
- backend/alembic/versions/e4a593920909_postgresql_single_source_of_truth_sync_.py (guard index/constraint ops)
- backend/.env (cleaned duplicate sqlite entry)   # note: this file should remain uncommitted
- backend/.env.example (placeholder values; default password changed to placeholder)
- docs/offline_sync_roadmap.md (added Local Postgres dev setup notes)

Testing:
- Ran `alembic upgrade head` against local Postgres (DATABASE_URL from `backend/.env`) successfully.
- Ran `pytest backend/tests/test_migrations.py::test_alembic_upgrade_head_against_postgres -q` (passed).
- Ran full backend test suite against local Postgres: `pytest -q` → All tests passed (33 passed, 0 failed).

Notes for reviewers:
- Confirm the guarded index/constraint logic is acceptable for migration strategy. It intentionally avoids failing on missing indexes/constraints to make re-runs safe. This is preferable in deployed environments where schema may have been partially migrated.
- Ensure CI runs migrations in a fresh DB and as part of the upgrade path, but the guarded checks will reduce flakiness for re-runs on existing DBs.

Follow-ups / Next steps:
- Add a small integration test in CI that runs `alembic upgrade head` twice to validate idempotency (optional).
- Create an automated migration smoke test for real Postgres in the CI pipeline.

---

If you'd like, I can create the branch and open the PR (I will need permission to push to your repo) or prepare the commit and give you the exact git commands to run locally.