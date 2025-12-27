from fastapi.testclient import TestClient
from src.main import app
from src.database import SessionLocal
from src.models import Product, Sale, SaleItem, InventoryLog, User, UserRole
from src.auth import get_password_hash
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


def get_token():
    ensure_superadmin()
    resp = client.post('/auth/token', data={'username': 'superbrian', 'password': os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')})
    assert resp.status_code == 200
    return resp.json()['access_token']


def test_superadmin_can_delete_product_any_store_including_dependent_rows():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create two stores
    rs1 = client.post('/api/stores', json={'name': 's1', 'location': 'loc1'}, headers=headers)
    rs2 = client.post('/api/stores', json={'name': 's2', 'location': 'loc2'}, headers=headers)
    assert rs1.status_code == 201 and rs2.status_code == 201
    s1 = rs1.json()['id']
    s2 = rs2.json()['id']

    # Create a product in store s1
    client.post(f'/api/stores/switch/{s1}', headers=headers)
    rp = client.post('/api/products', json={'name': 'global-del', 'price': 1.0, 'stock_quantity': 1}, headers=headers)
    assert rp.status_code == 201
    pid = rp.json()['id']

    # Insert dependent rows (sale item and inventory log) directly
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.username == 'superbrian').first()
        sale = Sale(user_id=user.id, store_id=s1, total_amount=1.0, payment_method='cash')
        db.add(sale)
        db.commit()
        db.refresh(sale)
        si = SaleItem(sale_id=sale.id, product_id=pid, quantity=1, unit_price=1.0, total_price=1.0)
        il = InventoryLog(product_id=pid, quantity_change=1, reason='restock', user_id=user.id)
        db.add_all([si, il])
        db.commit()
    finally:
        db.close()

    # Now attempt delete from global context (switch to s2 first to simulate different context)
    client.post(f'/api/stores/switch/{s2}', headers=headers)

    rd = client.delete(f'/api/products/{pid}', headers=headers)
    assert rd.status_code == 204

    # Verify product and dependent rows removed
    db = SessionLocal()
    try:
        p = db.query(Product).filter(Product.id == pid).first()
        assert p is None
        sis = db.query(SaleItem).filter(SaleItem.product_id == pid).all()
        ils = db.query(InventoryLog).filter(InventoryLog.product_id == pid).all()
        assert len(sis) == 0
        assert len(ils) == 0
    finally:
        db.close()

    # Cleanup stores
    client.delete(f'/api/stores/{s1}/hard', headers=headers)
    client.delete(f'/api/stores/{s2}/hard', headers=headers)
