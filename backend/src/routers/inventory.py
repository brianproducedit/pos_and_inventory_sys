from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime
from src.database import get_db
from src.auth import get_current_active_user
from src.models import InventoryLog, Product
from src.store_context import StoreContext, require_store_access
from src.audit_service import AuditService, AUDIT_ACTIONS
from src.schemas import InventoryLogResponse

router = APIRouter()

@router.get("/inventory/logs", response_model=List[InventoryLogResponse])
async def read_inventory_logs(
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Get inventory logs for the current store"""
    # Get products in current store to filter logs; if global view, use accessible stores or all
    prod_query = db.query(Product.id)
    if store_context.store_id is not None:
        prod_query = prod_query.filter(Product.store_id == store_context.store_id)
    else:
        if store_context.is_admin:
            store_ids = [s.id for s in store_context.get_accessible_stores(db)]
            prod_query = prod_query.filter(Product.store_id.in_(store_ids))
        # superadmin: no store filter

    product_ids = prod_query.subquery()
    logs = db.query(InventoryLog).filter(InventoryLog.product_id.in_(product_ids)).all()
    return [InventoryLogResponse.from_orm(log) for log in logs]

@router.post("/inventory/adjust")
async def adjust_inventory(
    adjustment_data: dict,
    request: Request,
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Adjust inventory for a product in the current store"""
    product_id = adjustment_data.get('product_id')
    quantity_change = adjustment_data.get('quantity_change')
    reason = adjustment_data.get('reason', 'adjustment')

    # Verify product belongs to current store
    product = db.query(Product).filter(
        Product.id == product_id,
        Product.store_id == store_context.store_id
    ).first()

    if not product:
        raise HTTPException(status_code=404, detail="Product not found in current store")

    # Create inventory log
    log = InventoryLog(
        product_id=product_id,
        quantity_change=quantity_change,
        reason=reason,
        user_id=store_context.user.id
    )
    db.add(log)

    # Update product stock
    product.stock_quantity += quantity_change
    product.updated_at = datetime.utcnow()

    db.commit()
    db.refresh(log)

    # Log the inventory adjustment
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=store_context.user.id,
        action=AUDIT_ACTIONS["UPDATE_PRODUCT"],
        resource_type="inventory",
        resource_id=log.id,
        details={
            "product_id": product_id,
            "product_name": product.name,
            "quantity_change": quantity_change,
            "new_stock": product.stock_quantity,
            "reason": reason,
            "store_id": store_context.store_id
        },
        ip_address=request.client.host,
        user_agent=request.headers.get("user-agent"),
        store_id=store_context.store_id
    )

    return {"message": "Inventory adjusted successfully", "new_stock": product.stock_quantity}

# Add low stock alerts
@router.get("/inventory/alerts")
async def inventory_alerts(
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Get low stock alerts for products in the current store"""
    alerts_q = db.query(Product).filter(
        Product.stock_quantity <= 10,
        Product.is_active == True
    )
    if store_context.store_id is not None:
        alerts_q = alerts_q.filter(Product.store_id == store_context.store_id)
    else:
        if store_context.is_admin:
            store_ids = [s.id for s in store_context.get_accessible_stores(db)]
            alerts_q = alerts_q.filter(Product.store_id.in_(store_ids))
        # superadmin sees all

    alerts = alerts_q.all()

    return [
        {
            "id": product.id,
            "name": product.name,
            "stock_quantity": product.stock_quantity,
            "alert_level": "Critical" if product.stock_quantity <= 5 else "Low"
        }
        for product in alerts
    ]