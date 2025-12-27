import os
from datetime import datetime, timedelta
import time
import json
from fastapi.testclient import TestClient
from src.main import app
from src.database import SessionLocal
from src.models import Store, Product, User

# Helper: create auth token for superadmin

from src.init_db import create_admin_user

def get_token(client, username='superadmin', password='testpw'):
    # Ensure admin exists for this test run
    create_admin_user()
    r = client.post('/auth/token', data={'username': username, 'password': password})
    assert r.status_code == 200, f"Auth failed: {r.text}"
    return r.json()['access_token']


def test_get_changes_returns_new_product(tmp_path, monkeypatch):
    # Setup DB file
    db_file = tmp_path / 'test_sync_get.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    client = TestClient(app)

    # Create a store + product directly
    db = SessionLocal()
    store = Store(name='Test Store')
    db.add(store)
    db.commit()
    db.refresh(store)

    # Create product
    p = Product(name='TestProd', price=9.99, stock_quantity=10, store_id=store.id)
    db.add(p)
    db.commit()
    db.refresh(p)

    # Query changes since 1 minute ago (authenticated)
    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}
    since = (datetime.utcnow() - timedelta(minutes=1)).isoformat()
    r = client.get(f"/api/sync/changes?since={since}&types=products", headers=headers)
    assert r.status_code == 200
    data = r.json()
    assert 'changes' in data
    products = data['changes'].get('products', [])
    assert any(prod['data']['name'] == 'TestProd' for prod in products)


def test_push_create_product(tmp_path, monkeypatch):
    db_file = tmp_path / 'test_sync_push_create.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    client = TestClient(app)

    # Seed: create store
    db = SessionLocal()
    store = Store(name='StorePush')
    db.add(store)
    db.commit()
    db.refresh(store)

    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    payload = {
        'client_id': 'cli1',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'create',
                'temp_id': 't1',
                'data': {
                    'name': 'PushedProd',
                    'description': 'Created via sync push',
                    'price': 12.5,
                    'stock_quantity': 7,
                    'store_id': store.id
                }
            }
        ]
    }

    r = client.post('/api/sync/push', json=payload, headers=headers)
    assert r.status_code == 200, r.text
    res = r.json()
    assert 'id_map' in res and 't1' in res['id_map']
    new_id = res['id_map']['t1']

    # Verify in DB
    db = SessionLocal()
    p = db.query(Product).filter(Product.id == new_id).first()
    assert p is not None
    assert p.name == 'PushedProd'


def test_push_conflict(tmp_path, monkeypatch):
    db_file = tmp_path / 'test_sync_conflict.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    client = TestClient(app)
    db = SessionLocal()
    store = Store(name='StoreConflict')
    db.add(store)
    db.commit()
    db.refresh(store)

    # Create product on server
    p = Product(name='ConflictProd', price=5.0, stock_quantity=2, store_id=store.id)
    db.add(p)
    db.commit()
    db.refresh(p)

    # Prepare an update with an older timestamp to force a conflict
    older_time = (p.updated_at - timedelta(seconds=10)).isoformat() if p.updated_at else (datetime.utcnow() - timedelta(days=1)).isoformat()

    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    payload = {
        'client_id': 'cli1',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'update',
                'id': p.id,
                'data': {'price': 4.0},
                'last_updated': older_time
            }
        ]
    }

    r = client.post('/api/sync/push', json=payload, headers=headers)
    assert r.status_code == 200
    res = r.json()
    assert 'conflicts' in res and len(res['conflicts']) > 0


def test_push_update_with_force(tmp_path, monkeypatch):
    db_file = tmp_path / 'test_sync_force.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    client = TestClient(app)
    db = SessionLocal()
    store = Store(name='StoreForce')
    db.add(store)
    db.commit()
    db.refresh(store)

    p = Product(name='ForceProd', price=20.0, stock_quantity=5, store_id=store.id)
    db.add(p)
    db.commit()
    db.refresh(p)

    # Make server have newer updated_at
    p.price = 22.0
    db.commit()
    db.refresh(p)

    older_time = (p.updated_at - timedelta(seconds=10)).isoformat()

    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    payload = {
        'client_id': 'cli-force',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'update',
                'id': p.id,
                'data': {'price': 18.0, '_force': True},
                'last_updated': older_time
            }
        ]
    }

    r = client.post('/api/sync/push', json=payload, headers=headers)
    assert r.status_code == 200, r.text
    res = r.json()
    # Should have applied the forced update
    assert any(a['operation'] == 'update' and a['id'] == p.id for a in res['applied'])

    db = SessionLocal()
    p2 = db.query(Product).filter(Product.id == p.id).first()
    assert p2.price == 18.0


def test_push_create_store(tmp_path, monkeypatch):
    db_file = tmp_path / 'test_sync_store.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    client = TestClient(app)

    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    payload = {
        'client_id': 'cli2',
        'changes': [
            {
                'resource_type': 'store',
                'operation': 'create',
                'temp_id': 's1',
                'data': {
                    'name': 'Synced Store',
                    'location': 'Test Location'
                }
            }
        ]
    }

    r = client.post('/api/sync/push', json=payload, headers=headers)
    assert r.status_code == 200
    res = r.json()
    assert 'id_map' in res and 's1' in res['id_map']
    new_id = res['id_map']['s1']

    db = SessionLocal()
    s = db.query(Store).filter(Store.id == new_id).first()
    assert s is not None
    assert s.name == 'Synced Store'


def test_push_create_user(tmp_path, monkeypatch):
    db_file = tmp_path / 'test_sync_user.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    client = TestClient(app)

    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    # Create store to assign to user
    db = SessionLocal()
    store = Store(name='UserStore')
    db.add(store)
    db.commit()
    db.refresh(store)

    payload = {
        'client_id': 'cli3',
        'changes': [
            {
                'resource_type': 'user',
                'operation': 'create',
                'temp_id': 'u1',
                'data': {
                    'username': 'syncuser',
                    'password': 'syncpass',
                    'role': 'admin',
                    'store_id': store.id
                }
            }
        ]
    }

    # Ensure test runs clean: remove any existing 'syncuser' left over from prior runs
    existing = db.query(User).filter(User.username == 'syncuser').first()
    if existing:
        db.delete(existing)
        db.commit()

    r = client.post('/api/sync/push', json=payload, headers=headers)
    assert r.status_code == 200
    res = r.json()
    assert 'id_map' in res and 'u1' in res['id_map']
    new_id = res['id_map']['u1']

    db = SessionLocal()
    u = db.query(User).filter(User.id == new_id).first()
    assert u is not None
    assert u.username == 'syncuser'
    assert u.role.name == 'admin'
