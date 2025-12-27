# Environment setup (Backend)

This file describes recommended setup steps for development, production (Postgres), and offline device installs (SQLite).

## Quick start (local, offline-friendly)
1. Copy `backend/.env.example` to `backend/.env` and adjust values.

Postgres setup (optional - for production-like testing):

- Ensure you have a Postgres instance reachable and point `DATABASE_URL` to it (example):

  DATABASE_URL=postgresql://postgres:postgres@localhost:5432/pos_dev

- Run Alembic migrations against Postgres (recommended in CI):

  cd backend
  alembic upgrade head

- To run local integration tests against Postgres, set `DATABASE_URL` in the environment or `.env` and run the test suite.

2. For local offline installs, use the default SQLite file (no change needed):
   - DATABASE_URL=sqlite:///pos_inventory.db
3. (Optional) To seed the default `superadmin` run:
   - `python backend/init_db.py`
4. To create a pruned minimal DB with only `superadmin`:
   - `python backend/scripts/prune_sqlite.py` or `python backend/scripts/prune_sqlite.py --replace` to overwrite the existing DB.

## Run with Postgres (production or server)
1. Update `backend/.env` or your environment with a Postgres URL, e.g.:
   - DATABASE_URL=postgresql://postgres:postgres@db:5432/pos_inventory_db
2. Start the Postgres service (e.g., `docker-compose up db` or use a managed Postgres service).
3. Run Alembic migrations:
   - `cd backend` and `alembic upgrade head` (make sure `DATABASE_URL` is set in env)
4. Seed the `superadmin` account if needed:
   - `python init_db.py`

## Notes & Best Practices
- Never commit your actual `.env` file into Git. Use `.env.example` as a template and keep `.env` in `.gitignore`.
- Consider using Docker secrets or a vault (e.g., AWS Secrets Manager) for production secrets, and avoid plaintext secrets in container definitions.
- Alembic's `env.py` already supports reading `DATABASE_URL` from the environment.

