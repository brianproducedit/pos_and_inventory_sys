from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from typing import Optional, List
from src.database import get_db
from src.auth import get_current_active_user
from src.models import Sale, SaleItem, Product, Store, User
from src.audit_service import AuditService, AUDIT_ACTIONS
from src.store_context import StoreContext, require_store_access
from src.schemas import SaleCreate, SaleResponse, SaleItemResponse

router = APIRouter()

@router.post("/sales", response_model=SaleResponse)
async def create_sale(
    sale_data: SaleCreate,
    request: Request,
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Create a new sale in the current store"""
    # Validate that all products belong to the current store
    product_ids = [item.product_id for item in sale_data.items]
    products = db.query(Product).filter(
        Product.id.in_(product_ids),
        Product.store_id == store_context.store_id,
        Product.is_active == True
    ).all()

    if len(products) != len(product_ids):
        raise HTTPException(status_code=400, detail="Some products not found or not available in current store")

    # Create the sale
    sale = Sale(
        total_amount=sale_data.total_amount,
        payment_method=sale_data.payment_method,
        paynow_reference=sale_data.paynow_reference,
        user_id=store_context.user.id,
        store_id=store_context.store_id
    )
    db.add(sale)
    db.commit()
    db.refresh(sale)

    # Create sale items and update stock
    sale_items = []
    for item_data in sale_data.items:
        product = next(p for p in products if p.id == item_data.product_id)
        if product.stock_quantity < item_data.quantity:
            raise HTTPException(
                status_code=400,
                detail=f"Insufficient stock for product {product.name}"
            )

        sale_item = SaleItem(
            sale_id=sale.id,
            product_id=item_data.product_id,
            quantity=item_data.quantity,
            unit_price=item_data.unit_price,
            total_price=item_data.quantity * item_data.unit_price
        )
        db.add(sale_item)
        sale_items.append(sale_item)

        # Update product stock
        product.stock_quantity -= item_data.quantity

    db.commit()

    # Log the sale creation
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=store_context.user.id,
        action=AUDIT_ACTIONS["CREATE_SALE"],
        resource_type="sale",
        resource_id=sale.id,
        details={
            "total_amount": sale.total_amount,
            "payment_method": sale.payment_method,
            "item_count": len(sale_data.items),
            "store_id": store_context.store_id
        },
        ip_address=request.client.host,
        user_agent=request.headers.get("user-agent"),
        store_id=store_context.store_id
    )

    # Return the complete sale with items
    sale.items = sale_items
    return SaleResponse.from_orm(sale)

@router.get("/receipts/{sale_id}")
async def get_receipt(
    sale_id: int,
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Get receipt for a sale in the current store"""
    sale = db.query(Sale).filter(
        Sale.id == sale_id,
        Sale.store_id == store_context.store_id
    ).first()

    if not sale:
        raise HTTPException(status_code=404, detail="Sale not found")

    # Get store information
    store = db.query(Store).filter(Store.id == sale.store_id).first()

    # Get cashier information
    cashier = db.query(User).filter(User.id == sale.user_id).first()

    items = db.query(SaleItem).filter(SaleItem.sale_id == sale_id).all()
    receipt_items = []
    for item in items:
        product = db.query(Product).filter(Product.id == item.product_id).first()
        receipt_items.append({
            "product_id": item.product_id,
            "product_name": product.name if product else "Unknown Product",
            "quantity": item.quantity,
            "unit_price": item.unit_price,
            "total_price": item.total_price
        })

    receipt = {
        "sale_id": sale.id,
        "total_amount": float(sale.total_amount),
        "payment_method": sale.payment_method,
        "paynow_reference": sale.paynow_reference,
        "created_at": sale.created_at.isoformat(),
        "items": receipt_items,
        "store": {
            "id": store.id if store else None,
            "name": store.name if store else "Unknown Store",
            "location": store.location if store else None
        } if store else None,
        "cashier": {
            "id": cashier.id if cashier else None,
            "username": cashier.username if cashier else "Unknown Cashier",
            "full_name": cashier.full_name if cashier else None
        } if cashier else None
    }
    return receipt

@router.get("/sales", response_model=List[SaleResponse])
async def read_sales(
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Get all sales for the current store"""
    sales = db.query(Sale).filter(Sale.store_id == store_context.store_id).all()
    return [SaleResponse.from_orm(sale) for sale in sales]

# Add analytics endpoint
@router.get("/analytics/sales")
async def sales_analytics(
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Get sales analytics for the current store"""
    from sqlalchemy import func, extract
    from datetime import datetime, timedelta

    # Base query: if a specific store is selected, scope to that store; otherwise use all stores
    sales_query = db.query(Sale)
    products_query = db.query(Product)
    if store_context.store_id is not None:
        sales_query = sales_query.filter(Sale.store_id == store_context.store_id)
        products_query = products_query.filter(Product.store_id == store_context.store_id)

    # Total sales and revenue
    total_sales = sales_query.count()
    total_revenue = sales_query.with_entities(func.sum(Sale.total_amount)).scalar() or 0.0

    # Daily sales for the last 7 days
    seven_days_ago = datetime.utcnow() - timedelta(days=7)
    daily_sales = []
    for i in range(7):
        day = seven_days_ago + timedelta(days=i)
        day_start = day.replace(hour=0, minute=0, second=0, microsecond=0)
        day_end = day.replace(hour=23, minute=59, second=59, microsecond=999999)

        day_sales = sales_query.filter(
            Sale.created_at >= day_start,
            Sale.created_at <= day_end
        ).with_entities(func.sum(Sale.total_amount)).scalar() or 0.0

        daily_sales.append({
            'date': day.strftime('%Y-%m-%d'),
            'revenue': float(day_sales)
        })

    # Top products by sales count
    top_products_q = db.query(
        Product.name,
        func.count(SaleItem.id).label('sales_count'),
        func.sum(SaleItem.total_price).label('total_revenue')
    ).join(SaleItem, Product.id == SaleItem.product_id)\
     .join(Sale, SaleItem.sale_id == Sale.id)

    if store_context.store_id is not None:
        top_products_q = top_products_q.filter(Sale.store_id == store_context.store_id)

    top_products = top_products_q.group_by(Product.id, Product.name)\
     .order_by(func.count(SaleItem.id).desc())\
     .limit(10)\
     .all()

    top_products_list = [
        {
            'name': product.name,
            'sales_count': product.sales_count,
            'total_revenue': float(product.total_revenue or 0)
        }
        for product in top_products
    ]

    # Recent sales (last 10)
    recent_sales = sales_query.order_by(Sale.created_at.desc()).limit(10).all()
    recent_sales_list = [
        {
            'id': sale.id,
            'total_amount': float(sale.total_amount),
            'created_at': sale.created_at.isoformat(),
            'items_count': len(sale.items)
        }
        for sale in recent_sales
    ]

    # Inventory alerts (low stock products)
    low_stock_products = products_query.filter(Product.stock_quantity <= 10).all()
    inventory_alerts = [
        {
            'id': product.id,
            'name': product.name,
            'stock_quantity': product.stock_quantity,
            'alert_level': 'Low Stock' if product.stock_quantity <= 5 else 'Medium Stock'
        }
        for product in low_stock_products
    ]

    return {
        'total_sales': total_sales,
        'total_revenue': float(total_revenue),
        'daily_sales': daily_sales,
        'top_products': top_products_list,
        'recent_sales': recent_sales_list,
        'inventory_alerts': inventory_alerts,
        'average_sale': float(total_revenue / total_sales) if total_sales > 0 else 0.0
    }