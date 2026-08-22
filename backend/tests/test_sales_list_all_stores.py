from fastapi.testclient import TestClient
from src.main import app
from src.models import Sale, SaleItem, Product, Store, User, UserRole
from src.database import SessionLocal
from src.auth import get_password_hash
from datetime import datetime
import os

client = TestClient(app)


def ensure_superadmin():
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.username == 'superbrian').first()
        if not user:
            test_pw = os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')
            user = User(username='superbrian', password_hash=get_password_hash(test_pw), role=UserRole.superadmin)
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


def test_sales_list_all_stores():
    db = SessionLocal()
    try:
        # Create two stores and products
        s1 = Store(name='S1')
        s2 = Store(name='S2')
        db.add_all([s1, s2])
        db.commit()
        db.refresh(s1); db.refresh(s2)
        p1 = Product(name='A', price=5.0, stock_quantity=10, store_id=s1.id)
        p2 = Product(name='B', price=7.0, stock_quantity=10, store_id=s2.id)
        db.add_all([p1, p2])
        db.commit()

        # Create a sale in store1 and one in store2
        usr = db.query(User).filter(User.username == 'superbrian').first()
        if not usr:
            test_pw = os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')
            usr = User(username='superbrian', password_hash=get_password_hash(test_pw), role=UserRole.superadmin)
            db.add(usr); db.commit(); db.refresh(usr)

        sA = Sale(transaction_number="TX-TEST", user_id=usr.id, store_id=s1.id, total_amount=10.0, payment_method='cash', created_at=datetime.utcnow())
        sB = Sale(transaction_number="TX-TEST", user_id=usr.id, store_id=s2.id, total_amount=14.0, payment_method='cash', created_at=datetime.utcnow())
        db.add_all([sA, sB])
        db.commit()
        # capture ids before closing the session to avoid DetachedInstanceError
        sA_id = sA.id
        sB_id = sB.id
    finally:
        db.close()

    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Switch to All Stores
    rs = client.post('/api/stores/switch/0', headers=headers)
    assert rs.status_code == 200

    # Request sales list (should include both sales)
    r = client.get('/api/sales', headers=headers)
    assert r.status_code == 200
    data = r.json()
    ids = {s['id'] for s in data}
    assert sA_id in ids and sB_id in ids, f"expected both sales, got {ids}"
