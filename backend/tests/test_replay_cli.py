import os
import sys
import io
import importlib
from contextlib import redirect_stdout
from src.database import SessionLocal
from src.services.sync_replay import replay_changes


def test_replay_cli_prints_report(tmp_path, monkeypatch):
    db_file = tmp_path / 'test_replay_cli.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    # Apply schema
    from tests.conftest import run_migrations
    run_migrations()

    # Insert a change row to replay
    db = SessionLocal()
    try:
        r = db.execute('SELECT COALESCE(MAX(server_seq), 0) + 1 as next_seq').fetchone()
        next_seq = r[0] if r else 1
    except Exception:
        next_seq = 1

    # Create a minimal product create change
    from sqlalchemy import text
    db.execute(text("INSERT INTO changes (entity_type, entity_id, operation, payload, server_seq) VALUES ('product', NULL, 'create', '{}', :seq)"), {'seq': next_seq})
    db.commit()

    # Run CLI main with args via monkeypatching argv and capture stdout
    monkeypatch.setattr(sys, 'argv', ['replay_changes.py', '--from', str(next_seq), '--to', str(next_seq), '--dry-run'])
    # Import the script module directly from its file path (not a package)
    import importlib.util
    script_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'scripts', 'replay_changes.py'))
    spec = importlib.util.spec_from_file_location('replay_changes_cli', script_path)
    script_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(script_mod)

    f = io.StringIO()
    with redirect_stdout(f):
        script_mod.main()
    out = f.getvalue()
    assert 'Processed' in out or 'Replay report' in out
    assert 'Would create product' in out or 'dry-run' in out
