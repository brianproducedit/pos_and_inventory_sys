from src.database import SessionLocal
from src.models import Store, Product, User, Sale, SaleItem, InventoryLog, StoreSettings, AuditLog, UserRole
from src.store_utils import hard_delete_store


def test_hard_delete_store_removes_all():
    db = SessionLocal()
    try:
        # Create store
        store = Store(name="hard_delete_store", location="test")
        db.add(store)
        db.commit()
        db.refresh(store)

        # Create product
        product = Product(name="p1", price=1.0, stock_quantity=10, store_id=store.id)
        db.add(product)
        db.commit()
        db.refresh(product)

        # Create a user assigned to store (use unique username to avoid collisions)
        import uuid
        unique_username = f"tmpadmin_{uuid.uuid4().hex[:8]}"
        user = User(username=unique_username, password_hash="x", role=UserRole.admin, store_id=store.id)
        db.add(user)
        db.commit()
        db.refresh(user)

        # Create a sale and sale item
        sale = Sale(transaction_number="TX-TEST", user_id=user.id, store_id=store.id, total_amount=10.0)
        db.add(sale)
        db.commit()
        db.refresh(sale)

        sale_item = SaleItem(sale_id=sale.id, product_id=product.id, quantity=1, unit_price=10.0, total_price=10.0)
        db.add(sale_item)
        db.commit()

        # Inventory log
        inv = InventoryLog(product_id=product.id, quantity_change=5, reason='restock', user_id=user.id)
        db.add(inv)
        db.commit()

        # Store settings, user-store mapping and audit log
        settings = StoreSettings(store_id=store.id, business_name='biz')
        db.add(settings)
        # Create a UserStore mapping (admin assigned to store)
        from src.models import UserStore
        mapping = UserStore(user_id=user.id, store_id=store.id)
        db.add(mapping)
        audit = AuditLog(user_id=user.id, store_id=store.id, action='TEST', resource_type='store', resource_id=store.id, details='{}', ip_address='127.0.0.1')
        db.add(audit)
        # Also add an audit log that references the user but not the store to reproduce the edge case
        audit_user_only = AuditLog(user_id=user.id, store_id=None, action='TEST2', resource_type='user', resource_id=user.id, details='{}', ip_address='127.0.0.1')
        db.add(audit_user_only)
        db.commit()

        # Capture ids before deletion
        sale_id = sale.id
        product_id = product.id

        # Now hard delete
        hard_delete_store(db, store.id)

        # Assert deletions
        assert db.query(Store).filter(Store.id == store.id).first() is None
        assert db.query(Product).filter(Product.store_id == store.id).count() == 0
        assert db.query(User).filter(User.store_id == store.id).count() == 0
        assert db.query(Sale).filter(Sale.store_id == store.id).count() == 0
        assert db.query(SaleItem).filter(SaleItem.sale_id == sale_id).count() == 0
        assert db.query(InventoryLog).filter(InventoryLog.product_id == product_id).count() == 0
        assert db.query(StoreSettings).filter(StoreSettings.store_id == store.id).count() == 0
        assert db.query(UserStore).filter(UserStore.store_id == store.id).count() == 0
        assert db.query(AuditLog).filter(AuditLog.store_id == store.id).count() == 0

    finally:
        db.close()
