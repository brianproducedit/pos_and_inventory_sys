import os
import importlib
from fastapi.testclient import TestClient
from src.models import Store, Product, Change
from src.init_db import create_admin_user


def get_token(client, username='superadmin', password='testpw'):
    import importlib
    import src.init_db
    importlib.reload(src.init_db)
    src.init_db.create_admin_user()
    r = client.post('/auth/token', data={'username': username, 'password': password})
    assert r.status_code == 200
    return r.json()['access_token']


def test_replay_update_applies_change(tmp_path, monkeypatch):
    db_file = tmp_path / 'test_replay_update.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    # Ensure migrations applied to the test DB so `changes` schema matches runtime expectations
    from tests.conftest import run_migrations
    run_migrations()

    # Import app after setting DATABASE_URL so the application uses the test DB
    import importlib
    import src.database
    importlib.reload(src.database)
    # Ensure main picks up the reloaded DB configuration
    try:
        importlib.reload(__import__('src.main'))
    except Exception:
        pass
    from src.main import app
    client = TestClient(app)
    from src.database import SessionLocal
    importlib.reload(src.database)
    db = SessionLocal()

    # Create store and product
    store = Store(name='ReplayStore')
    db.add(store)
    db.commit()
    db.refresh(store)

    p = Product(name='BeforeName', price=1.0, stock_quantity=1, store_id=store.id)
    db.add(p)
    db.commit()
    db.refresh(p)

    # Create a change via the sync push API to ensure DB schema compatibility
    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    push_payload = {
        'client_id': 'replay-test',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'update',
                'id': p.id,
                'data': {'name': 'ReplayedName'}
            }
        ]
    }

    r_push = client.post('/api/sync/push', json=push_payload, headers=headers)
    assert r_push.status_code == 200, r_push.text

    # Find or insert the change entry we will replay
    db = SessionLocal()
    try:
        ch = db.query(Change).filter(Change.entity_type == 'product', Change.entity_id == str(p.id), Change.operation == 'update').order_by(Change.server_seq.desc()).first()
    except Exception:
        ch = None

    if not ch:
        # Insert a minimal change row using ORM to be DB-agnostic
        from sqlalchemy import inspect, text
        inspector = inspect(db.bind)
        cols = [c['name'] for c in inspector.get_columns('changes')]

        # Ensure any previous failed transaction is rolled back so we can insert
        try:
            db.rollback()
        except Exception:
            pass

        # Try to pick a server_seq if DB requires it
        try:
            row = db.execute(text("SELECT COALESCE(MAX(server_seq), 0) + 1 as next_seq FROM changes")).fetchone()
            next_seq = row[0] if row else 1
        except Exception:
            next_seq = None

        change_kwargs = {'entity_type': 'product', 'entity_id': str(p.id), 'operation': 'update'}
        if 'payload' in cols:
            change_kwargs['payload'] = {"data": {"name": "ReplayedName"}}
        if 'origin_client_id' in cols:
            change_kwargs['origin_client_id'] = 'replay-test'
        if next_seq is not None:
            change_kwargs['server_seq'] = next_seq

        ch_obj = Change(**change_kwargs)
        db.add(ch_obj)
        db.commit()
        db.refresh(ch_obj)
        ch = ch_obj

    # Modify the product so replay needs to change it back
    p_in_db = db.query(Product).filter(Product.id == p.id).first()
    p_in_db.name = 'DifferentName'
    db.commit()
    db.refresh(p_in_db)
    p = p_in_db

    r = client.post('/api/admin/replay-changes', json={'from_seq': ch.server_seq, 'to_seq': ch.server_seq, 'dry_run': False}, headers=headers)
    assert r.status_code == 200, r.text
    res = r.json()
    assert res['processed'] == 1
    db = SessionLocal()
    p2 = db.query(Product).filter(Product.id == p.id).first()
    assert p2.name == 'ReplayedName'


def test_replay_create_skips_if_entity_exists(tmp_path):
    db_file = tmp_path / 'test_replay_create_skip.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    from tests.conftest import run_migrations
    run_migrations()

    importlib.reload(__import__('src.database'))
    try:
        importlib.reload(__import__('src.main'))
    except Exception:
        pass
    from src.main import app
    client = TestClient(app)
    from src.database import SessionLocal
    importlib.reload(__import__('src.database'))
    db = SessionLocal()

    # Pre-create a product that matches the change's entity_id
    store = Store(name='ReplayStoreSkip')
    db.add(store)
    db.commit()
    db.refresh(store)

    p = Product(name='Already', price=1.0, stock_quantity=1, store_id=store.id)
    db.add(p)
    db.commit()
    db.refresh(p)

    # Insert a create change referencing that id
    from sqlalchemy import text
    try:
        next_seq = db.execute(text("SELECT COALESCE(MAX(server_seq), 0) + 1 as next_seq FROM changes")).fetchone()[0]
    except Exception:
        next_seq = 1

    ch = Change(entity_type='product', entity_id=str(p.id), operation='create', payload={'data': {'name': 'Already'}}, server_seq=next_seq)
    db.add(ch)
    db.commit()
    db.refresh(ch)

    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    r = client.post('/api/admin/replay-changes', json={'from_seq': ch.server_seq, 'to_seq': ch.server_seq, 'dry_run': False}, headers=headers)
    assert r.status_code == 200, r.text
    res = r.json()
    assert res['processed'] == 1
    assert res['skipped'] == 1
    # ensure the product still exists and was not duplicated
    db = SessionLocal()
    prods = db.query(Product).filter(Product.name == 'Already', Product.store_id == store.id).all()
    assert len(prods) == 1


def test_replay_dry_run_does_not_apply(tmp_path, monkeypatch):
    db_file = tmp_path / 'test_replay_dryrun.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    # Ensure migrations applied to the test DB so `changes` schema matches runtime expectations
    from tests.conftest import run_migrations
    run_migrations()

    # Import app after setting DATABASE_URL so the application uses the test DB
    import importlib
    import src.database
    importlib.reload(src.database)
    # Ensure main picks up the reloaded DB configuration
    try:
        importlib.reload(__import__('src.main'))
    except Exception:
        pass
    from src.main import app
    client = TestClient(app)
    from src.database import SessionLocal
    importlib.reload(src.database)
    db = SessionLocal()

    store = Store(name='ReplayStore2')
    db.add(store)
    db.commit()
    db.refresh(store)

    p = Product(name='BeforeName2', price=2.0, stock_quantity=2, store_id=store.id)
    db.add(p)
    db.commit()
    db.refresh(p)

    # Create a change via the sync push API to ensure DB schema compatibility
    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    push_payload = {
        'client_id': 'replay-test-dr',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'update',
                'id': p.id,
                'data': {'name': 'ShouldNotApply'}
            }
        ]
    }

    r_push = client.post('/api/sync/push', json=push_payload, headers=headers)
    assert r_push.status_code == 200, r_push.text

    # Find or insert the change entry we will replay
    db = SessionLocal()
    try:
        ch = db.query(Change).filter(Change.entity_type == 'product', Change.entity_id == str(p.id), Change.operation == 'update').order_by(Change.server_seq.desc()).first()
    except Exception:
        ch = None

    if not ch:
        # Insert a minimal change row using ORM to be DB-agnostic
        from sqlalchemy import inspect, text
        inspector = inspect(db.bind)
        cols = [c['name'] for c in inspector.get_columns('changes')]

        # Ensure any previous failed transaction is rolled back so we can insert
        try:
            db.rollback()
        except Exception:
            pass

        # Try to pick a server_seq if DB requires it
        try:
            row = db.execute(text("SELECT COALESCE(MAX(server_seq), 0) + 1 as next_seq FROM changes")).fetchone()
            next_seq = row[0] if row else 1
        except Exception:
            next_seq = None

        change_kwargs = {'entity_type': 'product', 'entity_id': str(p.id), 'operation': 'update'}
        if 'payload' in cols:
            change_kwargs['payload'] = {"data": {"name": "ShouldNotApply"}}
        if 'origin_client_id' in cols:
            change_kwargs['origin_client_id'] = 'replay-test-dr'
        if next_seq is not None:
            change_kwargs['server_seq'] = next_seq

        ch_obj = Change(**change_kwargs)
        db.add(ch_obj)
        db.commit()
        db.refresh(ch_obj)
        ch = ch_obj

    # change name so dry-run would have applied
    p_in_db = db.query(Product).filter(Product.id == p.id).first()
    p_in_db.name = 'Changed'
    db.commit()
    db.refresh(p_in_db)
    p = p_in_db

    r = client.post('/api/admin/replay-changes', json={'from_seq': ch.server_seq, 'to_seq': ch.server_seq, 'dry_run': True}, headers=headers)
    assert r.status_code == 200, r.text
    res = r.json()
    assert res['processed'] == 1
    db = SessionLocal()
    p2 = db.query(Product).filter(Product.id == p.id).first()
    assert p2.name == 'Changed'
