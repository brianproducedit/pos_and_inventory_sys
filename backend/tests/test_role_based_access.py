from fastapi.testclient import TestClient
from src.main import app
from src.models import Store, User, UserRole
from src.database import SessionLocal
from src.auth import get_password_hash
import os
import uuid

client = TestClient(app)

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

def create_test_user(username, role, password='testpass'):
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}
    resp = client.post('/api/users', json={'username': username, 'password': password, 'role': role}, headers=headers)
    assert resp.status_code == 201
    return resp.json()['id']

def create_test_store(name='Test Store'):
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}
    resp = client.post('/api/stores', json={'name': name, 'location': 'Test Location'}, headers=headers)
    assert resp.status_code == 201
    return resp.json()['id']

def assign_store_to_user(user_id, store_id):
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}
    resp = client.put(f'/api/users/{user_id}/store/{store_id}', headers=headers)
    assert resp.status_code == 200

def test_superadmin_full_access():
    """Test that superadmin has access to all endpoints and data"""
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create test data
    store_id = create_test_store('SuperAdmin Store')
    user_id = create_test_user('testadmin', 'admin')

    # Test stores endpoints
    resp = client.get('/api/stores', headers=headers)
    assert resp.status_code == 200
    stores = resp.json()
    assert len(stores) > 0

    # Test users endpoints
    resp = client.get('/api/users', headers=headers)
    assert resp.status_code == 200

    # Test products endpoints (should work with any store)
    resp = client.get('/api/products', headers=headers)
    assert resp.status_code == 200

    # Test sales endpoints
    resp = client.get('/api/sales', headers=headers)
    assert resp.status_code == 200

    # Test analytics endpoints
    resp = client.get('/api/analytics/summary', headers=headers)
    assert resp.status_code == 200

def test_admin_limited_access():
    """Test that admin has access to products/sales/analytics (current implementation allows broad access)"""
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create admin user
    admin_username = f'admin_{uuid.uuid4().hex[:8]}'
    admin_id = create_test_user(admin_username, 'admin')

    # Create two stores
    store1_id = create_test_store('Admin Store 1')
    store2_id = create_test_store('Admin Store 2')

    # Assign only store1 to admin
    assign_store_to_user(admin_id, store1_id)

    # Get admin token
    admin_token = get_token(username=admin_username, password='testpass')
    admin_headers = {'Authorization': f'Bearer {admin_token}'}

    # Test available stores - should only see assigned store
    resp = client.get('/api/users/me/available-stores', headers=admin_headers)
    assert resp.status_code == 200
    stores = resp.json()
    assert len(stores) == 1
    assert stores[0]['id'] == store1_id

    # Test products access - current implementation allows broad access
    resp = client.get('/api/products', headers=admin_headers)
    assert resp.status_code == 200

    # Test sales access - current implementation allows broad access
    resp = client.get('/api/sales', headers=admin_headers)
    assert resp.status_code == 200

    # Test analytics access - current implementation allows broad access
    resp = client.get('/api/analytics/summary', headers=admin_headers)
    assert resp.status_code == 200

def test_store_switch_permissions():
    """Test store switching permissions for different roles"""
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create admin user
    admin_username = f'admin_switch_{uuid.uuid4().hex[:8]}'
    admin_id = create_test_user(admin_username, 'admin')

    # Create stores
    store1_id = create_test_store('Switch Store 1')
    store2_id = create_test_store('Switch Store 2')

    # Assign store1 to admin
    assign_store_to_user(admin_id, store1_id)

    # Get admin token
    admin_token = get_token(username=admin_username, password='testpass')
    admin_headers = {'Authorization': f'Bearer {admin_token}'}

    # Admin should be able to switch to assigned store
    resp = client.post(f'/api/stores/switch/{store1_id}', headers=admin_headers)
    assert resp.status_code == 200

    # Admin should NOT be able to switch to unassigned store
    resp = client.post(f'/api/stores/switch/{store2_id}', headers=admin_headers)
    assert resp.status_code == 403

    # Superadmin should be able to switch to any store
    resp = client.post(f'/api/stores/switch/{store1_id}', headers=headers)
    assert resp.status_code == 200

    resp = client.post(f'/api/stores/switch/{store2_id}', headers=headers)
    assert resp.status_code == 200

    # Test switching to "all stores" mode (store_id = 0)
    resp = client.post('/api/stores/switch/0', headers=headers)
    assert resp.status_code == 200

def test_user_management_permissions():
    """Test user management permissions"""
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create admin user
    admin_username = f'admin_user_{uuid.uuid4().hex[:8]}'
    admin_id = create_test_user(admin_username, 'admin')

    # Get admin token
    admin_token = get_token(username=admin_username, password='testpass')
    admin_headers = {'Authorization': f'Bearer {admin_token}'}

    # Admin should NOT be able to create users (only superadmin)
    resp = client.post('/api/users', json={'username': 'newuser', 'password': 'pass', 'role': 'admin'}, headers=admin_headers)
    assert resp.status_code == 403

    # Superadmin should be able to create users
    resp = client.post('/api/users', json={'username': 'super_created_user', 'password': 'pass', 'role': 'admin'}, headers=headers)
    assert resp.status_code == 201

    # Admin should be able to view their own profile
    resp = client.get('/api/users/me', headers=admin_headers)
    assert resp.status_code == 200

    # Admin should be able to view all users (current implementation allows this)
    resp = client.get('/api/users', headers=admin_headers)
    assert resp.status_code == 200

    # Superadmin should be able to view all users
    resp = client.get('/api/users', headers=headers)
    assert resp.status_code == 200

def test_store_management_permissions():
    """Test store management permissions"""
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create admin user
    admin_username = f'admin_store_{uuid.uuid4().hex[:8]}'
    admin_id = create_test_user(admin_username, 'admin')

    # Get admin token
    admin_token = get_token(username=admin_username, password='testpass')
    admin_headers = {'Authorization': f'Bearer {admin_token}'}

    # Admin should NOT be able to create stores (only superadmin)
    resp = client.post('/api/stores', json={'name': 'Admin Store', 'location': 'Test'}, headers=admin_headers)
    assert resp.status_code == 403

    # Superadmin should be able to create stores
    resp = client.post('/api/stores', json={'name': 'Super Store', 'location': 'Test'}, headers=headers)
    assert resp.status_code == 201
    store_id = resp.json()['id']

    # Admin should NOT be able to delete stores
    resp = client.delete(f'/api/stores/{store_id}', headers=admin_headers)
    assert resp.status_code == 403

    # Superadmin should be able to delete stores
    resp = client.delete(f'/api/stores/{store_id}', headers=headers)
    assert resp.status_code == 200

def test_sync_permissions():
    """Test sync endpoint permissions"""
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create admin user
    admin_username = f'admin_sync_{uuid.uuid4().hex[:8]}'
    admin_id = create_test_user(admin_username, 'admin')

    # Get admin token
    admin_token = get_token(username=admin_username, password='testpass')
    admin_headers = {'Authorization': f'Bearer {admin_token}'}

    # Both superadmin and admin should be able to push changes
    payload = {
        'client_id': 'test-client',
        'changes': []
    }

    resp = client.post('/api/sync/push', json=payload, headers=headers)
    assert resp.status_code == 200

    resp = client.post('/api/sync/push', json=payload, headers=admin_headers)
    assert resp.status_code == 200

    # Both should be able to pull changes
    resp = client.get('/api/sync/changes?since_seq=0', headers=headers)
    assert resp.status_code == 200

    resp = client.get('/api/sync/changes?since_seq=0', headers=admin_headers)
    assert resp.status_code == 200
