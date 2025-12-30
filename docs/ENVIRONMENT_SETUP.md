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

---

## Flutter client environment & test notes 📱
Add the following environment variables (or set them via build-time config) to configure network endpoints used by the mobile client:

- `BASE_URL` — Base API URL for the server (e.g., `https://api.example.com` or `http://localhost:8000`).

Testing & local runs:
- For widget/unit tests that touch network code, always inject or override HTTP clients and providers instead of relying on real network calls. Examples:
  - Override `postgresApiServiceProvider` in tests using `ProviderScope(overrides: [postgresApiServiceProvider.overrideWithValue(fakeService)])`.
  - Use `SharedPreferences.setMockInitialValues({'access_token': 'tok'})` in tests that expect a stored token.
- Use `sqflite_common_ffi` (in-memory DB) in tests to avoid platform sqlite issues: call `sqfliteFfiInit()` and set `databaseFactory = databaseFactoryFfi` before database use.
- When testing UI interactions that schedule background tasks or DB reads, avoid `pumpAndSettle()` if background timers or unbounded futures are present; prefer explicit `tester.pump()` calls and polling the database or provider state with a bounded timeout instead.

Seed / initial data instructions:
- Manual (dev): In the app, open `Sync Demo` and press the **Seed DB (initial fetch)** button (requires a valid `access_token` stored in prefs). This calls the server endpoint to fetch initial snapshot and seeds the local DB.
- Tests: Prefer calling `PostgresApiService.fetchInitialDataAndSeedDB` directly in a test with a fake API client to verify seeding behavior deterministically.

CI notes:
- Provide `BASE_URL` via CI secrets (e.g., `BASE_URL`) if running integration tests that need a backend. Prefer mock-based tests in CI to avoid flaky network.

---

If you want, I can add a short troubleshooting checklist to this file explaining common test failures (DB locks, off-screen button taps, missing token, HttpClient warnings).
