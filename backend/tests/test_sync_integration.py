import os
import importlib
from datetime import datetime, timedelta
from fastapi.testclient import TestClient
from src.models import Store, Product

from tests.test_replay import get_token


def _setup_app(tmp_path):
    db_file = tmp_path / 'test_sync_integration.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    # Apply migrations or create schema for SQLite fast-path
    from tests.conftest import run_migrations
    run_migrations()

    # Reload DB modules and app so they pick up the test DATABASE_URL
    importlib.reload(__import__('src.database'))
    try:
        importlib.reload(__import__('src.main'))
    except Exception:
        pass
    from src.main import app
    client = TestClient(app)
    # Ensure session factory reflects reload
    importlib.reload(__import__('src.database'))
    from src.database import SessionLocal
    return client, SessionLocal


def test_push_create_idempotent(tmp_path):
    client, SessionLocal = _setup_app(tmp_path)
    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    db = SessionLocal()
    store = Store(name='IntegrationStore')
    db.add(store)
    db.commit()
    db.refresh(store)

    payload = {
        'client_id': 'cid-1',
        'changes': [
            {'resource_type': 'product', 'operation': 'create', 'temp_id': 't123', 'data': {'name': 'ProdX', 'store_id': store.id}}
        ]
    }

    r1 = client.post('/api/sync/push', json=payload, headers=headers)
    assert r1.status_code == 200, r1.text
    j1 = r1.json()
    assert 't123' in j1.get('id_map', {}), j1
    assigned_id = j1['id_map']['t123']

    # Repeat same create; should map to same server id and not create duplicate
    r2 = client.post('/api/sync/push', json=payload, headers=headers)
    assert r2.status_code == 200, r2.text
    j2 = r2.json()
    assert j2.get('id_map', {}).get('t123') == assigned_id

    db = SessionLocal()
    prods = db.query(Product).filter(Product.name == 'ProdX', Product.store_id == store.id).all()
    assert len(prods) == 1


def test_push_update_conflict(tmp_path):
    client, SessionLocal = _setup_app(tmp_path)
    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    db = SessionLocal()
    store = Store(name='IntegrationStore2')
    db.add(store)
    db.commit()
    db.refresh(store)

    p = Product(name='Before', price=5.0, stock_quantity=10, store_id=store.id)
    db.add(p)
    db.commit()
    db.refresh(p)

    # Simulate server side newer update
    p.name = 'ServerNew'
    p.updated_at = datetime.utcnow() + timedelta(minutes=5)
    db.commit()
    db.refresh(p)

    # Client attempts update with an older timestamp
    client_payload = {
        'client_id': 'cid-2',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'update',
                'id': p.id,
                'last_updated': (datetime.utcnow() - timedelta(days=1)).isoformat(),
                'data': {'name': 'ClientUpdate'}
            }
        ]
    }

    r = client.post('/api/sync/push', json=client_payload, headers=headers)
    assert r.status_code == 200, r.text
    j = r.json()
    assert j.get('conflicts') and len(j['conflicts']) == 1
    c = j['conflicts'][0]
    assert 'Conflict' in c['message'] or 'server has newer' in c['message']
    assert c.get('suggestion') == 'fetch_or_force'


def test_pull_changes_ordering(tmp_path):
    client, SessionLocal = _setup_app(tmp_path)
    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    db = SessionLocal()
    s = Store(name='IntegrationStore3')
    db.add(s)
    db.commit()
    db.refresh(s)

    # Push two creates which should record two change rows with increasing server_seq
    payload = {
        'client_id': 'cid-3',
        'changes': [
            {'resource_type': 'product', 'operation': 'create', 'temp_id': 't-a', 'data': {'name': 'A', 'store_id': s.id}},
            {'resource_type': 'product', 'operation': 'create', 'temp_id': 't-b', 'data': {'name': 'B', 'store_id': s.id}}
        ]
    }

    r = client.post('/api/sync/push', json=payload, headers=headers)
    assert r.status_code == 200, r.text

    # Pull changes since_seq=0
    r2 = client.get('/api/sync/changes?since_seq=0', headers=headers)
    assert r2.status_code == 200, r2.text
    j2 = r2.json()
    changes = j2.get('changes', [])
    assert len(changes) >= 2

    # verify ordering by server_seq
    seqs = [c['server_seq'] for c in changes if c.get('server_seq') is not None]
    assert seqs == sorted(seqs)

    # head_seq should be >= the last seq returned
    assert j2.get('head_seq') >= max(seqs)
