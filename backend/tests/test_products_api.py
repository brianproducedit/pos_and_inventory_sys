from fastapi.testclient import TestClient
from src.main import app
from src.database import SessionLocal
from src.models import Store

client = TestClient(app)


from src.auth import get_password_hash
from src.models import User, UserRole
import os


def ensure_superadmin():
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.username == 'superbrian').first()
        if not user:
            test_pw = os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')
            user = User(username='superbrian', password_hash=get_password_hash(test_pw), role=UserRole.superadmin)
            db.add(user)
            db.commit()
        else:
            test_pw = os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')
            user.password_hash = get_password_hash(test_pw)
            user.role = UserRole.superadmin
            db.commit()
    finally:
        db.close()


def get_token():
    ensure_superadmin()
    resp = client.post('/auth/token', data={'username': 'superbrian', 'password': os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')})
    assert resp.status_code == 200
    return resp.json()['access_token']


def test_create_product_endpoint():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create a store to attach product to
    resp_store = client.post('/api/stores', json={'name': 'api-store', 'location': 'here'}, headers=headers)
    assert resp_store.status_code == 201
    store_id = resp_store.json()['id']

    # Switch to the created store so product creation has store context
    rs = client.post(f'/api/stores/switch/{store_id}', headers=headers)
    assert rs.status_code == 200

    # Create product
    resp_prod = client.post('/api/products', json={'name': 'papi', 'price': 9.99, 'stock_quantity': 5, 'is_active': True}, headers=headers)
    # Debug output for failing status
    if resp_prod.status_code != 201:
        print('create product failed:', resp_prod.status_code, resp_prod.text)
    assert resp_prod.status_code == 201
    prod = resp_prod.json()
    assert prod['name'] == 'papi'
    assert prod['price'] == 9.99
    assert prod['store_id'] == store_id

    # Cleanup - hard delete store
    rd = client.delete(f'/api/stores/{store_id}/hard', headers=headers)
    assert rd.status_code == 200
