from fastapi.testclient import TestClient
from src.main import app
from src.models import Store, User, UserRole
from src.database import SessionLocal

client = TestClient(app)

from src.auth import get_password_hash
import os


def ensure_superadmin():
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.username == 'superbrian').first()
        if not user:
            test_pw = os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')
            user = User(username='superbrian', password_hash=get_password_hash(test_pw), role=UserRole.superadmin, must_change_password=True)
            db.add(user)
            db.commit()
        else:
            # Ensure the must_change_password flag is set for tests, even if the user already exists
            if not getattr(user, 'must_change_password', False):
                user.must_change_password = True
                db.add(user)
                db.commit()
    finally:
        db.close()


def get_token(username='superbrian', password=None):
    pw = password or os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')
    ensure_superadmin()
    resp = client.post('/auth/token', data={'username': username, 'password': pw})
    assert resp.status_code == 200
    return resp.json()['access_token']


def test_available_stores_for_superadmin():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create two stores (one active, one inactive)
    resp1 = client.post('/api/stores', json={'name': 'Store A', 'location': 'A'}, headers=headers)
    assert resp1.status_code == 201
    resp2 = client.post('/api/stores', json={'name': 'Store B', 'location': 'B', 'is_active': False}, headers=headers)
    assert resp2.status_code == 201

    # Superadmin should see active store(s)
    resp = client.get('/api/users/me/available-stores', headers=headers)
    assert resp.status_code == 200
    stores = resp.json()
    # Only active stores expected
    assert any(s['name'] == 'Store A' for s in stores)
    assert all(s['is_active'] for s in stores)


def test_available_stores_for_admin_with_assignments():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create admin user
    import uuid
    admin_username = f'admin_{uuid.uuid4().hex[:8]}'
    resp = client.post('/api/users', json={'username': admin_username, 'password': 'pass', 'role': 'admin'}, headers=headers)
    assert resp.status_code == 201
    admin_id = resp.json()['id']

    # Create two stores and assign only one
    r1 = client.post('/api/stores', json={'name': 'Admin Store 1', 'location': 'X'}, headers=headers)
    r2 = client.post('/api/stores', json={'name': 'Admin Store 2', 'location': 'Y'}, headers=headers)
    s1 = r1.json()['id']
    s2 = r2.json()['id']

    # Assign store s1 to admin
    ra = client.put(f'/api/users/{admin_id}/store/{s1}', headers=headers)
    assert ra.status_code == 200

    # Authenticate as admin
    token_admin = get_token(username=admin_username, password='pass')
    headers_admin = {'Authorization': f'Bearer {token_admin}'}

    # Admin should see only assigned stores
    resp = client.get('/api/users/me/available-stores', headers=headers_admin)
    assert resp.status_code == 200
    stores = resp.json()
    assert len(stores) >= 1
    assert any(s['id'] == s1 for s in stores), f"admin available stores: {stores}"
    # Ensure store s2 is not listed unless admin has access
    assert not any(s['id'] == s2 for s in stores)


def test_superadmin_must_change_password_flag():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}
    resp = client.get('/api/users/me', headers=headers)
    assert resp.status_code == 200
    me = resp.json()
    assert 'must_change_password' in me
    assert me['must_change_password'] == True
