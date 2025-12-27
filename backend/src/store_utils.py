from sqlalchemy.orm import Session
from sqlalchemy import or_
from fastapi import HTTPException, status
from src.models import (
    Store,
    Sale,
    SaleItem,
    Product,
    InventoryLog,
    User,
    UserRole,
    StoreSettings,
    AuditLog,
    AnalyticsEvent,
)


def hard_delete_store(db: Session, store_id: int):
    """Perform a hard delete of a store and all related data.

    This deletes in order to satisfy foreign key constraints:
    - SaleItems belonging to sales of the store
    - Sales belonging to the store
    - InventoryLogs for products belonging to the store
    - Products for the store
    - Users assigned to the store
    - StoreSettings for the store
    - AuditLogs referencing the store
    - The store itself
    """
    store = db.query(Store).filter(Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Store not found")

    # Sales and SaleItems
    sale_ids = [s.id for s in db.query(Sale.id).filter(Sale.store_id == store_id).all()]
    if sale_ids:
        db.query(SaleItem).filter(SaleItem.sale_id.in_(sale_ids)).delete(synchronize_session=False)
        db.query(Sale).filter(Sale.id.in_(sale_ids)).delete(synchronize_session=False)

    # Products and InventoryLogs
    product_ids = [p.id for p in db.query(Product.id).filter(Product.store_id == store_id).all()]
    if product_ids:
        db.query(InventoryLog).filter(InventoryLog.product_id.in_(product_ids)).delete(synchronize_session=False)
        db.query(Product).filter(Product.id.in_(product_ids)).delete(synchronize_session=False)

    # Remove user-store mapping entries for this store (to allow deleting users)
    from src.models import UserStore, UserSettings
    db.query(UserStore).filter(UserStore.store_id == store_id).delete(synchronize_session=False)

    # Audit logs related to this store (delete before users to avoid FK violations on AuditLog.user_id)
    db.query(AuditLog).filter(AuditLog.store_id == store_id).delete(synchronize_session=False)

    # Delete any records referencing users assigned to this store (some logs may reference users without a store ref)
    user_ids = [u.id for u in db.query(User.id).filter(User.store_id == store_id, User.role != UserRole.superadmin).all()]
    if user_ids:
        db.query(AuditLog).filter(AuditLog.user_id.in_(user_ids)).delete(synchronize_session=False)
        db.query(InventoryLog).filter(InventoryLog.user_id.in_(user_ids)).delete(synchronize_session=False)
        db.query(AnalyticsEvent).filter(AnalyticsEvent.user_id.in_(user_ids)).delete(synchronize_session=False)
        db.query(UserSettings).filter(UserSettings.user_id.in_(user_ids)).delete(synchronize_session=False)
        # Also remove any user-store mappings for these users
        db.query(UserStore).filter(UserStore.user_id.in_(user_ids)).delete(synchronize_session=False)

    # Users assigned to this store (skip superadmins)
    db.query(User).filter(User.store_id == store_id, User.role != UserRole.superadmin).delete(synchronize_session=False)

    # Store settings
    db.query(StoreSettings).filter(StoreSettings.store_id == store_id).delete(synchronize_session=False)

    # Analytics events referencing this store (from/to)
    db.query(AnalyticsEvent).filter(or_(AnalyticsEvent.from_store_id == store_id, AnalyticsEvent.to_store_id == store_id)).delete(synchronize_session=False)

    # Finally, delete the store. Rely on DB-level ON DELETE CASCADE for related mappings.
    try:
        db.delete(store)
        db.commit()
    except Exception as e:
        db.rollback()
        # Gather counts of potential remaining references for diagnostics
        remaining = {
            'analytics_events': db.query(AnalyticsEvent).filter(or_(AnalyticsEvent.from_store_id == store_id, AnalyticsEvent.to_store_id == store_id)).count(),
            'user_stores': db.execute("SELECT COUNT(*) FROM user_stores WHERE store_id = :id", {'id': store_id}).scalar(),
            'products': db.query(Product).filter(Product.store_id == store_id).count(),
            'sales': db.query(Sale).filter(Sale.store_id == store_id).count(),
            'store_settings': db.query(StoreSettings).filter(StoreSettings.store_id == store_id).count(),
            'users': db.query(User).filter(User.store_id == store_id).count(),
        }
        detail = f"{e} - Remaining refs: {remaining}"
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=detail)

    return {"message": "Store and all related data deleted successfully", "store_id": store_id}
