from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from src.database import get_db
from src.models import Store, User, AnalyticsEvent, UserRole
from src.store_context import StoreContext, get_store_context
from src.schemas import StoreResponse, StoreCreate, StoreCreate
from src.auth import get_current_active_user
from datetime import datetime
import json

router = APIRouter(prefix="/api/stores", tags=["stores"])

@router.post("", response_model=StoreResponse)
async def create_store(
    store_data: StoreCreate,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Create a new store"""
    # Only superadmin and admin can create stores
    if current_user.role not in [UserRole.superadmin, UserRole.admin]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to create stores"
        )

    # Create the store
    new_store = Store(
        name=store_data.name,
        location=store_data.location,
        is_active=store_data.is_active,
        created_by=current_user.id
    )

    try:
        db.add(new_store)
        db.commit()
        db.refresh(new_store)
        return StoreResponse.from_orm(new_store)
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create store: {str(e)}"
        )

@router.get("", response_model=List[StoreResponse])
async def get_my_stores(
    store_context: StoreContext = Depends(get_store_context),
    db: Session = Depends(get_db)
):
    """Get stores that the current user can access"""
    stores = store_context.get_accessible_stores(db)
    return [StoreResponse.from_orm(store) for store in stores]

@router.get("/current")
async def get_current_store(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get the current store for the user, or None for All Stores"""
    print(f"get_current_store: user_id={current_user.id}, username={current_user.username}, store_id={current_user.store_id}")
    if current_user.store_id is None:
        print("get_current_store: user has no store_id, returning null")
        return {'current_store': None}
    store = db.query(Store).filter(Store.id == current_user.store_id, Store.is_active == True).first()
    if store:
        print(f"get_current_store: found store id={store.id}, name={store.name}")
        # Use model_validate + model_dump to convert ORM object to dict for proper JSON serialization
        store_data = StoreResponse.model_validate(store).model_dump()
        response = {'current_store': store_data}
        print(f"get_current_store: returning {response}")
        return response
    else:
        # If the stored store is not found or inactive, return None
        print(f"get_current_store: store not found for store_id={current_user.store_id}")
        return {'current_store': None}

@router.post("/switch/{store_id}")
async def switch_store(
    store_id: int,
    store_context: StoreContext = Depends(get_store_context),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Switch to a different store context and persist it on the user record"""
    print(f"switch_store: user_id={current_user.id} requested_store_id={store_id}")
    start_ts = datetime.utcnow()
    new_context = store_context.switch_store(store_id, db)

    # Persist the user's current store so subsequent requests without X-Store-ID use it
    prev_store_id = current_user.store_id
    duration_ms = None
    success = False
    try:
        current_user.store_id = new_context.store_id
        current_user.updated_at = datetime.utcnow()
        db.commit()
        duration_ms = int((datetime.utcnow() - start_ts).total_seconds() * 1000)
        success = True
        print(f"switch_store: success user_id={current_user.id} to_store_id={new_context.store_id} duration_ms={duration_ms}")
    except Exception:
        db.rollback()
        duration_ms = int((datetime.utcnow() - start_ts).total_seconds() * 1000)
        success = False
        print(f"switch_store: failed to persist user {current_user.id} store switch duration_ms={duration_ms}")

    # Attempt to fetch store for richer response when not global
    store = None
    if new_context.store_id:
        store = db.query(Store).filter(Store.id == new_context.store_id).first()

    # Log a server-side analytics event for the store switch
    try:
        # Store structured info in metadata_json (e.g., success)
        metadata = json.dumps({'success': success})
        ae = AnalyticsEvent(
            event_name='store_switch',
            user_id=current_user.id,
            from_store_id=prev_store_id,
            to_store_id=new_context.store_id,
            duration_ms=duration_ms,
            metadata_json=metadata,
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