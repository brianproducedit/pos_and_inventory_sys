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

    # Also verify change was recorded and visible via server_seq pull
    r2 = client.get(f"/api/sync/changes?since_seq=0&types=product", headers=headers)
    assert r2.status_code == 200, r2.text
    data = r2.json()
    assert 'changes' in data
    changes = data['changes']
    assert any(ch.get('entity_type') == 'product' and ch.get('entity_id') == str(new_id) and ch.get('operation') == 'create' for ch in changes)



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

    # Verify change is visible via server_seq pull
    r2 = client.get(f"/api/sync/changes?since_seq=0&types=store", headers=headers)
    assert r2.status_code == 200, r2.text
    data = r2.json()
    assert any(ch.get('entity_type') == 'store' and ch.get('entity_id') == str(new_id) and ch.get('operation') == 'create' for ch in data['changes'])


def test_push_create_idempotent(tmp_path, monkeypatch):
    db_file = tmp_path / 'test_sync_idemp.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    client = TestClient(app)

    # Create store to assign to product
    db = SessionLocal()
    store = Store(name='IdempStore')
    db.add(store)
    db.commit()
    db.refresh(store)

    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    payload = {
        'client_id': 'cli-idemp',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'create',
                'temp_id': 'tid-1',
                'data': {
                    'name': 'IdempProd',
                    'price': 1.5,
                    'stock_quantity': 3,
                    'store_id': store.id
                }
            }
        ]
    }

    r1 = client.post('/api/sync/push', json=payload, headers=headers)
    assert r1.status_code == 200
    res1 = r1.json()
    assert 'id_map' in res1 and 'tid-1' in res1['id_map']
    id1 = res1['id_map']['tid-1']

    # Repeat same push
    r2 = client.post('/api/sync/push', json=payload, headers=headers)
    assert r2.status_code == 200
    res2 = r2.json()
    assert 'id_map' in res2 and 'tid-1' in res2['id_map']
    id2 = res2['id_map']['tid-1']

    assert id1 == id2

    db = SessionLocal()
    prods = db.query(Product).filter(Product.name == 'IdempProd').all()
    assert len(prods) == 1


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


def test_push_create_product_missing_store_returns_400(tmp_path, monkeypatch):
    db_file = tmp_path / 'test_sync_push_create_missing_store.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    client = TestClient(app)

    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    payload = {
        'client_id': 'cli4',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'create',
                'temp_id': 't_missing',
                'data': {
                    'name': 'NoStoreProd',
                    'price': 3.5,
                    'stock_quantity': 1
                }
            }
        ]
    }

    r = client.post('/api/sync/push', json=payload, headers=headers)
    assert r.status_code == 400
    assert 'store_id' in r.json().get('detail', '')


def test_get_initial_data(tmp_path, monkeypatch):
    # Setup DB file
    db_file = tmp_path / 'test_initial.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    client = TestClient(app)

    # Create test data
    db = SessionLocal()
    store = Store(name='Test Store', location='Test Location')
    db.add(store)
    db.commit()
    db.refresh(store)

    # Create products
    p1 = Product(name='TestProd1', price=9.99, stock_quantity=10, store_id=store.id)
    p2 = Product(name='TestProd2', price=19.99, stock_quantity=5, store_id=store.id, is_active=False)  # inactive
    db.add(p1)
    db.add(p2)
    db.commit()
    db.refresh(p1)
    db.refresh(p2)

    # Query initial data (authenticated)
    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}
    r = client.get("/api/sync/initial", headers=headers)
    assert r.status_code == 200
    data = r.json()

    # Check structure
    assert 'products' in data
    assert 'stores' in data
    assert 'server_time' in data

    # Check products (should only include active ones)
    products = data['products']
    assert len(products) == 1  # Only active product
    assert products[0]['name'] == 'TestProd1'
    assert products[0]['price'] == 9.99
    assert products[0]['store_id'] == store.id

    # Check stores
    stores = data['stores']
    assert len(stores) == 1
    assert stores[0]['name'] == 'Test Store'
    assert stores[0]['location'] == 'Test Location'
