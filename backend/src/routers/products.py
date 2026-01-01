from fastapi import APIRouter, Depends, HTTPException, Body, Request, Response
from sqlalchemy.orm import Session
from typing import List
from src.database import get_db
from src.auth import get_current_active_user
from src.models import Product, UserRole, SaleItem, InventoryLog
from src.audit_service import AuditService, AUDIT_ACTIONS
from src.store_context import StoreContext, require_store_access
from src.schemas import ProductCreate, ProductUpdate, ProductResponse
from datetime import datetime

router = APIRouter()

@router.get("/products", response_model=List[ProductResponse])
async def read_products(
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Get products for the current store context"""
    query = db.query(Product).filter(Product.is_active == True)
    if store_context.store_id is not None:
        query = query.filter(Product.store_id == store_context.store_id)
    else:
        # global view: if admin, limit to accessible stores; superadmin sees all
        if store_context.is_admin:
            store_ids = [s.id for s in store_context.get_accessible_stores(db)]
            query = query.filter(Product.store_id.in_(store_ids))

    products = query.all()
    return [ProductResponse.from_orm(product) for product in products]

@router.get("/products/all", response_model=List[ProductResponse])
async def read_all_products(
    include_inactive: bool = False,
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Get all products for the current store context, optionally including inactive"""
    query = db.query(Product)

    # If a specific store is selected, scope to it; otherwise allow superadmin or admin (accessible stores)
    if store_context.store_id is not None:
        query = query.filter(Product.store_id == store_context.store_id)
    else:
        if store_context.is_admin:
            store_ids = [s.id for s in store_context.get_accessible_stores(db)]
            query = query.filter(Product.store_id.in_(store_ids))
        # superadmin sees all stores (no additional filter)

    if not include_inactive:
        query = query.filter(Product.is_active == True)

    products = query.all()
    return [ProductResponse.from_orm(product) for product in products]

@router.post("/products", response_model=ProductResponse, status_code=201)
async def create_product(
    product_data: ProductCreate,
    request: Request,
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Create a new product in the current store"""
    # Validate store context
    if not store_context.store_id:
        raise HTTPException(status_code=400, detail="Store context not set. Specify X-Store-ID header or switch to a store.")

    pdata = product_data.dict(exclude_unset=True)
    # Ensure store context and default active status
    pdata['store_id'] = store_context.store_id
    if 'is_active' not in pdata:
        pdata['is_active'] = True

    try:
        product = Product(**pdata)
        db.add(product)
        db.commit()
        db.refresh(product)
    except Exception as e:
        # Log and surface a useful error message
        print(f"Error creating product: {e}")
        db.rollback()
        raise HTTPException(status_code=400, detail=f"Unable to create product: {e}")

    # Log the product creation
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=store_context.user.id,
        action=AUDIT_ACTIONS["CREATE_PRODUCT"],
        resource_type="product",
        resource_id=product.id,
        details={
            "product_name": product.name,
            "product_price": product.price,
            "store_id": store_context.store_id
        },
        ip_address=request.client.host,
        user_agent=request.headers.get("user-agent"),
        store_id=store_context.store_id
    )

    return ProductResponse.from_orm(product)

@router.put("/products/{product_id}", response_model=ProductResponse)
async def update_product(
    product_id: int,
    product_data: ProductUpdate,
    request: Request,
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Update a product in the current store"""
    product = db.query(Product).filter(
        Product.id == product_id,
        Product.store_id == store_context.store_id
    ).first()

    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    # Update product fields
    update_data = product_data.dict(exclude_unset=True)
    for key, value in update_data.items():
        if hasattr(product, key):
            setattr(product, key, value)

    product.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(product)

    # Log the product update
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=store_context.user.id,
        action=AUDIT_ACTIONS["UPDATE_PRODUCT"],
        resource_type="product",
        resource_id=product.id,
        details={
            "updated_fields": list(update_data.keys()),
            "store_id": store_context.store_id
        },
        ip_address=request.client.host,
        user_agent=request.headers.get("user-agent"),
        store_id=store_context.store_id
    )

    return ProductResponse.from_orm(product)

@router.delete("/products/{product_id}")
async def delete_product(
    product_id: int,
    request: Request,
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Delete a product from the current store"""
    # Try to find product within the current store context
    product = db.query(Product).filter(
        Product.id == product_id,
        Product.store_id == store_context.store_id
    ).first()

    # If not found in scoped query, try a global lookup if user has privileges
    if not product:
        alt = db.query(Product).filter(Product.id == product_id).first()
        if not alt:
            # No such product anywhere -> idempotent success
            return Response(status_code=204)

        # If user is superadmin they may delete across stores
        if store_context.is_superadmin:
            product = alt
        # Admins may delete if they can access the product's store
        elif store_context.is_admin and store_context.can_access_store(alt.store_id, db):
            product = alt
        else:
            # User lacks permission to delete this product; be explicit
            raise HTTPException(status_code=403, detail="You do not have permission to delete this product")

    # Delete dependent rows first to ensure referential integrity is maintained
    sale_items_deleted = db.query(SaleItem).filter(SaleItem.product_id == product.id).delete()
    inventory_logs_deleted = db.query(InventoryLog).filter(InventoryLog.product_id == product.id).delete()

    from src.routers.sync import _make_change

    # Record the deletion in the sync change log so it propagates to all clients
    try:
        _make_change(db, entity_type='product', entity_id=str(product.id), operation='delete', payload={}, origin_client_id=None)
    except Exception as e:
        # Log but don't fail the deletion if sync recording fails
        print(f"Warning: Failed to record product delete in sync log: {e}")

    # Delete the product
    db.delete(product)
    db.commit()

    # Log the product deletion action
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=store_context.user.id,
        action=AUDIT_ACTIONS["DELETE_PRODUCT"],
        resource_type="product",
        resource_id=product.id,
        details={
            "product_name": product.name,
            "product_price": product.price,
            "store_id": product.store_id,
            "sale_items_deleted": sale_items_deleted,
            "inventory_logs_deleted": inventory_logs_deleted,
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        store_id=product.store_id
    )

    # Return 204 No Content for successful deletion
    return Response(status_code=204)

@router.patch("/products/{product_id}/status", response_model=ProductResponse)
async def update_product_status(
    product_id: int,
    request: Request,
    status_update: dict = Body(...),
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Update product active status in the current store"""
    product = db.query(Product).filter(
        Product.id == product_id,
        Product.store_id == store_context.store_id
    ).first()

    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    old_status = product.is_active
    product.is_active = status_update.get('is_active', product.is_active)
    product.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(product)

    # Log the product status update action
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=store_context.user.id,
        action=AUDIT_ACTIONS["UPDATE_PRODUCT"],
        resource_type="product",
        resource_id=product.id,
        details={
            "updated_fields": ["is_active"],
            "old_status": old_status,
            "new_status": product.is_active,
            "store_id": store_context.store_id
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        store_id=store_context.store_id
    )

    return ProductResponse.from_orm(product)