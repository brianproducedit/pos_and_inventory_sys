from src.database import SessionLocal, get_engine
from src.models import Change
from sqlalchemy import text
import os

print('DATABASE_URL env:', os.getenv('DATABASE_URL', 'Not set'))
engine = get_engine()
print('Engine URL:', engine.url)

db = SessionLocal()
try:
    # Check if changes table exists - try both SQLite and PostgreSQL syntax
    try:
        if str(engine.url).startswith('sqlite'):
            result = db.execute(text('SELECT name FROM sqlite_master WHERE type="table" AND name="changes"'))
        else:
            result = db.execute(text("SELECT table_name FROM information_schema.tables WHERE table_name='changes'"))
        if result.fetchone():
            print('Changes table exists')
            # Check if it has data
            count = db.query(Change).count()
            print(f'Changes table has {count} records')
        else:
            print('Changes table does not exist')
    except Exception as e:
        print(f'Error checking table: {e}')
except Exception as e:
    print(f'Error: {e}')
finally:
    db.close()