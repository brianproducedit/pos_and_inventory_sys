"""Utility to ensure alembic_version table contains the merge head revision.
Run: python backend/scripts/stamp_alembic.py
"""
import os
from sqlalchemy import create_engine, text

def main():
    db_url = os.environ.get('DATABASE_URL')
    if not db_url:
        raise SystemExit('DATABASE_URL env var required')
    engine = create_engine(db_url)
    with engine.begin() as conn:
        conn.execute(text("CREATE TABLE IF NOT EXISTS alembic_version (version_num VARCHAR(32) NOT NULL)"))
        conn.execute(text("INSERT INTO alembic_version (version_num) SELECT :rev WHERE NOT EXISTS (SELECT 1 FROM alembic_version WHERE version_num=:rev)"), {'rev': 'mrg0001'})
        print('alembic_version set to include mrg0001')

if __name__ == '__main__':
    main()
