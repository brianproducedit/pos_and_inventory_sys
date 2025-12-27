#!/bin/sh
set -e

# Entry point: wait for DB readiness, run migrations, seed, then exec the server
DB_CHECK_RETRIES=${DB_CHECK_RETRIES:-15}
DB_CHECK_INTERVAL=${DB_CHECK_INTERVAL:-3}

echo "Checking database connectivity (trying $DB_CHECK_RETRIES times)..."
count=0
until python - <<'PY'
import os, sys
from sqlalchemy import create_engine
try:
    db_url = os.environ.get('DATABASE_URL')
    if not db_url:
        sys.exit(1)
    engine = create_engine(db_url)
    conn = engine.connect()
    conn.close()
except Exception:
    sys.exit(1)
sys.exit(0)
PY
do
  count=$((count+1))
  echo "Database not ready (attempt $count/$DB_CHECK_RETRIES); sleeping $DB_CHECK_INTERVAL seconds..."
  if [ "$count" -ge "$DB_CHECK_RETRIES" ]; then
    echo "Database did not become ready after $DB_CHECK_RETRIES attempts"
    exit 1
  fi
  sleep $DB_CHECK_INTERVAL
done

# Run alembic migrations with retry
echo "Running alembic migrations..."
max=10
i=0
until alembic upgrade head; do
  i=$((i+1))
  echo "Alembic failed (attempt $i/$max) — retrying in 3s"
  if [ "$i" -ge "$max" ]; then
    echo "Alembic failed after $max attempts — aborting"
    exit 1
  fi
  sleep 3
done

# Seed superadmin
echo "Seeding superadmin (if missing)..."
python init_db.py || echo "Seeding failed or already applied"

# Start the server
echo "Starting server: $@"
exec "$@"
