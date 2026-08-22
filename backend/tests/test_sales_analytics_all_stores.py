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


def test_sales_analytics_aggregates_all_stores():
    db = SessionLocal()
    try:
        # Create two stores
        s1 = Store(name='Harare Branch', location='Harare')
        s2 = Store(name='Bulawayo Branch', location='Bulawayo')
        db.add_all([s1, s2])
        db.commit()
        db.refresh(s1)
        db.refresh(s2)
        s1_id = s1.id
        s2_id = s2.id

        # Create a product in Harare
        p1 = Product(name='Widget', price=10.0, stock_quantity=100, store_id=s1_id)
        db.add(p1)
        db.commit()
        db.refresh(p1)

        # Ensure a user exists and create a sale in Harare with one item
        usr = db.query(User).filter(User.username == 'superbrian').first()
        if not usr:
            test_pw = os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')
            usr = User(username='superbrian', password_hash=get_password_hash(test_pw), role=UserRole.superadmin)
            db.add(usr)
            db.commit()
            db.refresh(usr)
        sale = Sale(transaction_number="TX-TEST", user_id=usr.id, store_id=s1_id, total_amount=20.0, payment_method='cash', created_at=datetime.utcnow())
        db.add(sale)
        db.commit()
        db.refresh(sale)

        item = SaleItem(sale_id=sale.id, product_id=p1.id, quantity=2, unit_price=10.0, total_price=20.0)
        db.add(item)
        db.commit()

    finally:
        db.close()
    # Get token and switch to All Stores (global)
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Check analytics without switching (should be scoped to current user store default which is None for superadmin)
    ra0 = client.get('/api/analytics/sales', headers=headers)
    assert ra0.status_code == 200
    print('SALES ANALYTICS BEFORE SWITCH:', ra0.json())

    rs = client.post('/api/stores/switch/0', headers=headers)
    assert rs.status_code == 200
    print('SWITCH RESP:', rs.json())

    # Verify the DB actually contains the sale we created
    db = SessionLocal()
    try:
        db_count = db.query(Sale).count()
        assert db_count >= 1
    finally:
        db.close()

    # Request sales analytics (should aggregate across stores)
    ra = client.get('/api/analytics/sales', headers=headers)
    assert ra.status_code == 200
    data = ra.json()
    print('SALES ANALYTICS RESPONSE:', data)
    # We created 1 sale in Harare; total_sales should reflect that
    assert data['total_sales'] >= 1, f"unexpected response: {data}"

    # Now switch to Harare store and verify totals for that store
    rs2 = client.post(f'/api/stores/switch/{s1_id}', headers=headers)
    assert rs2.status_code == 200

    ra2 = client.get('/api/analytics/sales', headers=headers)
    assert ra2.status_code == 200
    data2 = ra2.json()
    assert data2['total_sales'] >= 1
