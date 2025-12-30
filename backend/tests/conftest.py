import sys
import os

# Ensure backend project root is on sys.path so tests can import src.*
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

# Helper to run alembic migrations against the currently configured DATABASE_URL
from alembic.config import Config
from alembic import command

def run_migrations():
    """Apply alembic migrations to the DB pointed at by env var DATABASE_URL."""
    cfg = Config(os.path.join(ROOT, 'alembic.ini'))
    db_url = os.getenv('DATABASE_URL')
    if not db_url:
        raise RuntimeError('DATABASE_URL is not set; cannot run migrations')

    # For SQLite test DBs, it's more reliable to create tables from models than to run
    # the full Alembic migrations which can contain dialect-specific operations.
    if db_url.startswith('sqlite'):
        from sqlalchemy import create_engine
        from src.models import Base
        engine = create_engine(db_url, connect_args={"check_same_thread": False})
        Base.metadata.create_all(bind=engine)
        return

    # For non-SQLite DBs, run full alembic upgrade
    cfg.set_main_option('sqlalchemy.url', db_url)
    command.upgrade(cfg, 'head')

