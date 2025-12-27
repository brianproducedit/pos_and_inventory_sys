import os
import pytest
from alembic.config import Config
from alembic import command


def test_alembic_upgrade_head_against_postgres():
    db_url = os.getenv('DATABASE_URL', '')
    # Skip if not postgres (CI will set DATABASE_URL to postgres)
    if not db_url.startswith('postgres'):
        pytest.skip('Postgres DATABASE_URL not configured; skipping integration migration test')

    cfg = Config(os.path.join(os.path.dirname(__file__), '..', 'alembic.ini'))
    cfg.set_main_option('sqlalchemy.url', db_url)

    # Run upgrade head and ensure it completes without exception
    command.upgrade(cfg, 'head')

    # If we reach here, migrations applied successfully; assert a known table exists by querying
    # Use SQLAlchemy to inspect the DB
    from sqlalchemy import create_engine, inspect

    engine = create_engine(db_url)
    insp = inspect(engine)
    tables = insp.get_table_names()
    assert 'users' in tables or 'user' in tables
