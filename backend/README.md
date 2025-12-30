# Backend README

## Setup
1. Create virtual environment: `python -m venv venv`
2. Activate: `venv\Scripts\activate` (Windows)
3. Install dependencies: `pip install -r requirements.txt`
4. Copy `.env.example` to `.env` and fill in actual values
5. Run: `uvicorn src.main:app --reload` or `python -m uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload`
python -m uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload

## Environment Variables
- `DATABASE_URL`: Database connection string
- `SECRET_KEY`: JWT secret key
- `PAYNOW_INTEGRATION_ID`: Paynow integration ID
- `PAYNOW_INTEGRATION_KEY`: Paynow integration key

## Structure
- `src/`: Source code
- `tests/`: Unit tests
- Alembic migrations in `alembic/versions/`


flutter pub run build_runner build --delete-conflicting-outputs

Add server-side filters (by date range, store) exposed in the UI and also serach functionlity.