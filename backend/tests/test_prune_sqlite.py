import os
import sqlite3
import subprocess
import tempfile
from pathlib import Path
import pytest


def create_sample_db(path: str):
    conn = sqlite3.connect(path)
    cur = conn.cursor()
    # Create a minimal users table matching src/models.User
    cur.execute('''
    CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL,
        must_change_password BOOLEAN NOT NULL DEFAULT 0
    );
    ''')
    # Insert a non-admin user
    cur.execute("INSERT INTO users (username, password_hash, role, must_change_password) VALUES ('bob', 'x', 'staff', 0);")
    conn.commit()
    conn.close()


def run_prune_script(db_path: str):
    env = os.environ.copy()
    env['DATABASE_URL'] = f'sqlite:///{db_path}'
    # Execute the prune script via subprocess
    subprocess.check_call(["python", "scripts/prune_sqlite.py"], env=env)


def test_prune_creates_pruned_db(tmp_path: Path):
    orig = tmp_path / 'pos_inventory.db'
    create_sample_db(str(orig))

    # Run prune script
    run_prune_script(str(orig))

    pruned = tmp_path / 'pos_inventory.pruned.db'
    assert pruned.exists(), 'Pruned DB should be created'

    # Check pruned DB contains superadmin only
    conn = sqlite3.connect(str(pruned))
    cur = conn.cursor()
    cur.execute('SELECT username, role, must_change_password FROM users')
    rows = cur.fetchall()
    assert len(rows) == 1
    username, role, must_change = rows[0]
    assert username == os.getenv('DEFAULT_SUPERADMIN_USERNAME', 'superadmin')
    assert role.lower() in ('superadmin',)
    assert must_change in (0, 1)
    conn.close()


def test_prune_refuses_non_sqlite(tmp_path: Path):
    env = os.environ.copy()
    env['DATABASE_URL'] = 'postgresql://user:pass@localhost/doesnotmatter'
    with pytest.raises(subprocess.CalledProcessError):
        subprocess.check_call(["python", "scripts/prune_sqlite.py"], env=env)
