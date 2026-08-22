from fastapi.testclient import TestClient
from src.main import app
from src.database import SessionLocal
from src.models import Product, Sale, SaleItem, User, UserRole
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


def test_delete_product_removes_row_and_sale_items():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create a store and switch into it
    resp_store = client.post('/api/stores', json={'name': 't_store', 'location': 'here'}, headers=headers)
    assert resp_store.status_code == 201
    store_id = resp_store.json()['id']
    rs = client.post(f'/api/stores/switch/{store_id}', headers=headers)
    assert rs.status_code == 200

    # Create a product in that store
    rp = client.post('/api/products', json={'name': 'to-delete', 'price': 1.0, 'stock_quantity': 10}, headers=headers)
    assert rp.status_code == 201
    prod_id = rp.json()['id']

    # Add a sale and a sale item referencing the product (direct DB insertion)
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.username == 'superbrian').first()
        sale = Sale(transaction_number="TX-TEST", user_id=user.id, store_id=store_id, total_amount=1.0, payment_method='cash')
        db.add(sale)
        db.commit()
        db.refresh(sale)
        si = SaleItem(sale_id=sale.id, product_id=prod_id, quantity=1, unit_price=1.0, total_price=1.0)
        db.add(si)
        db.commit()
    finally:
        db.close()

    # Delete the product via API
    rd = client.delete(f'/api/products/{prod_id}', headers=headers)
    assert rd.status_code == 204

    # A subsequent delete should be idempotent and return 204 (no-op)
    rd_again = client.delete(f'/api/products/{prod_id}', headers=headers)
    assert rd_again.status_code == 204

    # Verify the product row is gone and sale_items referencing it are deleted
    db = SessionLocal()
    try:
        p = db.query(Product).filter(Product.id == prod_id).first()
        assert p is None
        sis = db.query(SaleItem).filter(SaleItem.product_id == prod_id).all()
        assert len(sis) == 0
    finally:
        db.close()

    # Cleanup - hard delete the store
    rd2 = client.delete(f'/api/stores/{store_id}/hard', headers=headers)
    assert rd2.status_code == 200
