from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from src.database import get_db
from src.models import Store, User, AnalyticsEvent
from src.store_context import StoreContext, get_store_context
from src.schemas import StoreResponse
from src.auth import get_current_active_user
from datetime import datetime

router = APIRouter(prefix="/api/stores", tags=["stores"])

@router.get("", response_model=List[StoreResponse])
async def get_my_stores(
    store_context: StoreContext = Depends(get_store_context),
    db: Session = Depends(get_db)
):
    """Get stores that the current user can access"""
    stores = store_context.get_accessible_stores(db)
    return [StoreResponse.from_orm(store) for store in stores]

@router.post("/switch/{store_id}")
async def switch_store(
    store_id: int,
    store_context: StoreContext = Depends(get_store_context),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Switch to a different store context and persist it on the user record"""
    new_context = store_context.switch_store(store_id, db)

    # Persist the user's current store so subsequent requests without X-Store-ID use it
    try:
        prev_store_id = current_user.store_id
        current_user.store_id = new_context.store_id
        current_user.updated_at = datetime.utcnow()
        db.commit()
    except Exception:
        db.rollback()

    # Attempt to fetch store for richer response when not global
    store = None
    if new_context.store_id:
        store = db.query(Store).filter(Store.id == new_context.store_id).first()

    # Log a server-side analytics event for the store switch
    try:
        ae = AnalyticsEvent(
            event_name='store_switch',
            user_id=current_user.id,
            from_store_id=prev_store_id,
            to_store_id=new_context.store_id,
            duration_ms=None,
            metadata_json=None,
            ip_address=None,
            user_agent=None,
        )
        db.add(ae)
        db.commit()
    except Exception:
        db.rollback()
    return {
        "message": "Store switched successfully",
        "current_store": {
            "id": new_context.store_id,
            "name": store.name if store else None
        }
    }

@router.get("/current")
async def get_current_store(
    store_context: StoreContext = Depends(get_store_context),
    db: Session = Depends(get_db)
):
    """Get current store information"""
    if not store_context.store_id:
        return {"current_store": None}

    store = db.query(Store).filter(
        Store.id == store_context.store_id,
        Store.is_active == True
    ).first()

    if not store:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Current store not found"
        )

    return {
        "current_store": {
            "id": store.id,
            "name": store.name,
            "location": store.location,
            "is_active": store.is_active
        }
    }