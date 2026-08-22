# POS & Inventory — Backend

FastAPI and PostgreSQL backend for the POS & Inventory system. 

Provides JWT authentication, role-based access control, and robust background synchronization endpoints for offline-first Flutter clients.

## Quick Start
See the [root README](../README.md) for the project overview and architecture.

For running this backend via Docker or locally, refer to the [Local Setup Guide](../docs/LOCAL_SETUP.md).

## Project Structure
- `src/` — Main FastAPI application, models, routers, and services
- `tests/` — Pytest suite
- `alembic/` — Database migrations
- `requirements.txt` — Python dependencies

## Testing
To run the automated tests:
```bash
pip install -r requirements.txt
python -m pytest
```