from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from src.database import get_db
from src.auth import get_current_active_user, get_password_hash
from src.models import User, Store, UserRole, UserStore
from src.audit_service import AuditService, AUDIT_ACTIONS
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

router = APIRouter()

class UserCreate(BaseModel):
    username: str
    password: str
    role: str
    store_id: Optional[int] = None
    full_name: Optional[str] = None

class UserUpdate(BaseModel):
    username: Optional[str] = None
    password: Optional[str] = None
    role: Optional[str] = None
    store_id: Optional[int] = None
    full_name: Optional[str] = None
    is_active: Optional[bool] = None

class StoreCreate(BaseModel):
    name: str
    location: Optional[str] = None

class StoreUpdate(BaseModel):
    name: Optional[str] = None
    location: Optional[str] = None
    is_active: Optional[bool] = None

class StoreResponse(BaseModel):
    id: int
    name: str
    location: Optional[str] = None
    is_active: bool
    created_by: Optional[int] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

    @classmethod
    def from_orm(cls, store):
        return cls(
            id=store.id,
            name=store.name,
            location=store.location,
            is_active=store.is_active,
            created_by=store.created_by,
            created_at=store.created_at,
            updated_at=store.updated_at,
        )

class UserResponse(BaseModel):
    id: int
    username: str
    full_name: Optional[str] = None
    role: str
    is_active: bool = True  # Default to True
    store_id: Optional[int] = None
    must_change_password: Optional[bool] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

    @classmethod
    def from_orm(cls, user):
        return cls(
            id=user.id,
            username=user.username,
            full_name=user.full_name,
            role=user.role.value if hasattr(user.role, 'value') else str(user.role),
            is_active=user.is_active if user.is_active is not None else True,
            store_id=user.store_id,
            must_change_password=user.must_change_password if hasattr(user, 'must_change_password') else None,
            created_at=user.created_at,
            updated_at=user.updated_at,
        )

@router.post("/users", response_model=UserResponse, status_code=201)
async def create_user(user: UserCreate, request: Request, db: Session = Depends(get_db), current_user = Depends(get_current_active_user)):
    if current_user.role.value not in ["superadmin", "admin"]:
        raise HTTPException(status_code=403, detail="Not authorized")

    if current_user.role.value == "admin" and user.role != "cashier":
        raise HTTPException(status_code=403, detail="Admins can only create cashiers")

    # For admin, ensure store_id is their store
    if current_user.role.value == "admin":
        if user.store_id != current_user.store_id:
            raise HTTPException(status_code=403, detail="Cannot assign to different store")

    # Hash password
    hashed_password = get_password_hash(user.password)
    new_user = User(username=user.username, password_hash=hashed_password, role=user.role, store_id=user.store_id, full_name=user.full_name)

    try:
        db.add(new_user)
        db.commit()
        db.refresh(new_user)

        # Log audit event
        audit_service = AuditService(db)
        audit_service.log_activity(
            user_id=current_user.id,
            action=AUDIT_ACTIONS['CREATE_USER'],
            resource_type='user',
            resource_id=new_user.id,
            details={
                'created_username': user.username,
                'created_role': user.role,
                'created_store_id': user.store_id
            },
            ip_address=request.client.host if request.client else None,
            user_agent=request.headers.get('user-agent')
        )

        return UserResponse.from_orm(new_user)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail="Username already exists")

@router.post("/stores", status_code=201)
async def create_store(store: StoreCreate, request: Request, db: Session = Depends(get_db), current_user = Depends(get_current_active_user)):
    if current_user.role.value != "superadmin":
        raise HTTPException(status_code=403, detail="Only superadmin can create stores")
    
    new_store = Store(name=store.name, location=store.location, created_by=current_user.id)
    db.add(new_store)
    db.commit()
    db.refresh(new_store)
    
    # Log the store creation
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=current_user.id,
        action=AUDIT_ACTIONS["CREATE_STORE"],
        resource_type="store",
        resource_id=new_store.id,
        details={
            "store_name": store.name,
            "store_location": store.location
        },
        ip_address=request.client.host,
        user_agent=request.headers.get("user-agent")
    )
    
    return StoreResponse.from_orm(new_store)

@router.put("/users/{user_id}/store/{store_id}")
async def assign_store_to_user(user_id: int, store_id: int, request: Request, db: Session = Depends(get_db), current_user = Depends(get_current_active_user)):
    if current_user.role.value != "superadmin":
        raise HTTPException(status_code=403, detail="Only superadmin can assign stores")
    
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    store = db.query(Store).filter(Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store not found")

    # If assigning to a cashier, keep legacy single-assignment behavior (store_id)
    if user.role == UserRole.cashier:
        user.store_id = store_id
        db.commit()
    else:
        # For admins (and other non-cashier roles), create an assignment mapping allowing multiple stores
        existing = db.query(UserStore).filter(
            UserStore.user_id == user_id,
            UserStore.store_id == store_id
        ).first()
        if not existing:
            assign = UserStore(user_id=user_id, store_id=store_id)
            db.add(assign)
            db.commit()

        # Ensure the user's persisted current store is set if not already
        if user.store_id is None:
            user.store_id = store_id
            db.commit()

    # Log the store assignment
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=current_user.id,
        action=AUDIT_ACTIONS["ASSIGN_STORE"],
        resource_type="user",
        resource_id=user.id,
        details={
            "assigned_store_id": store_id,
            "store_name": store.name,
            "user_role": user.role.value
        },
        ip_address=request.client.host,
        user_agent=request.headers.get("user-agent")
    )
    
    return {"message": "Store assigned successfully"}

@router.get("/users", response_model=List[UserResponse])
async def read_users(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    role: Optional[str] = None,
    store_id: Optional[int] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    query = db.query(User)

    # Role-based filtering
    if current_user.role == UserRole.superadmin:
        # Superadmin can see all users
        pass
    elif current_user.role == UserRole.admin:
        # Admin can see cashiers in their store and other admins
        query = query.filter(
            ((User.role == UserRole.cashier) & (User.store_id == current_user.store_id)) |
            (User.role == UserRole.admin)
        )
    else:
        # Cashiers can only see themselves
        query = query.filter(User.id == current_user.id)

    # Additional filters
    if role:
        query = query.filter(User.role == role)
    if store_id:
        query = query.filter(User.store_id == store_id)

    users = query.offset(skip).limit(limit).all()
    return [UserResponse.from_orm(user) for user in users]

@router.get("/users/me")
async def read_current_user(current_user: User = Depends(get_current_active_user)):
    return {
        "id": current_user.id,
        "username": current_user.username,
        "full_name": current_user.full_name,
        "role": current_user.role.value if hasattr(current_user.role, 'value') else str(current_user.role),
        "is_active": current_user.is_active,
        "store_id": current_user.store_id,
        "must_change_password": current_user.must_change_password,
        "created_at": current_user.created_at.isoformat(),
        "updated_at": current_user.updated_at.isoformat(),
    }

@router.get("/users/me/available-stores", response_model=List[StoreResponse])
async def available_stores(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Return stores available to the current user based on role and assignments"""
    from src.store_context import StoreContext
    ctx = StoreContext(current_user)
    stores = ctx.get_accessible_stores(db)
    return [StoreResponse.from_orm(s) for s in stores]

class ProfileUpdate(BaseModel):
    full_name: Optional[str] = None
    username: Optional[str] = None

class PasswordChange(BaseModel):
    current_password: str
    new_password: str

@router.put("/users/me/profile")
async def update_current_user_profile(
    profile_data: ProfileUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Update current user's profile information"""
    user = db.query(User).filter(User.id == current_user.id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # Update fields
    update_data = profile_data.dict(exclude_unset=True)
    for field, value in update_data.items():
        setattr(user, field, value)

    user.updated_at = datetime.utcnow()

    try:
        db.commit()
        db.refresh(user)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail="Username already exists")

    # Log the profile update action
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=current_user.id,
        action=AUDIT_ACTIONS["UPDATE_USER"],
        resource_type="user",
        resource_id=user.id,
        details={
            "updated_fields": list(update_data.keys()),
            "profile_update": True
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent")
    )

    return {
        "id": user.id,
        "username": user.username,
        "full_name": user.full_name,
        "role": user.role.value if hasattr(user.role, 'value') else str(user.role),
        "is_active": user.is_active,
        "store_id": user.store_id,
        "must_change_password": user.must_change_password,
        "created_at": user.created_at.isoformat(),
        "updated_at": user.updated_at.isoformat(),
    }

@router.put("/users/me/password")
async def change_current_user_password(
    password_data: PasswordChange,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Change current user's password"""
    from src.auth import verify_password

    user = db.query(User).filter(User.id == current_user.id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # Verify current password
    if not verify_password(password_data.current_password, user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")

    # Hash new password
    user.password_hash = get_password_hash(password_data.new_password)
    user.updated_at = datetime.utcnow()

    db.commit()
    db.refresh(user)
    
    # Log the password change action
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=current_user.id,
        action=AUDIT_ACTIONS["CHANGE_PASSWORD"],
        resource_type="user",
        resource_id=user.id,
        details={
            "password_changed": True,
            "user_role": user.role.value
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent")
    )

    return {"message": "Password changed successfully"}

@router.get("/users/{user_id}", response_model=UserResponse)
async def read_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # Permission checks
    if current_user.role == UserRole.superadmin:
        pass  # Can view all users
    elif current_user.role == UserRole.admin:
        if user.role == UserRole.superadmin:
            raise HTTPException(status_code=403, detail="Not authorized")
        if user.role == UserRole.admin and user.id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized")
        if user.role == UserRole.cashier and user.store_id != current_user.store_id:
            raise HTTPException(status_code=403, detail="Not authorized")
    else:
        if user.id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized")

    return UserResponse.from_orm(user)

@router.delete("/users/{user_id}")
async def delete_user(
    user_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # Permission checks
    if current_user.role == UserRole.superadmin:
        pass  # Can deactivate all users
    elif current_user.role == UserRole.admin:
        if user.role == UserRole.superadmin:
            raise HTTPException(status_code=403, detail="Not authorized")
        if user.role == UserRole.admin and user.id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized")
        if user.role == UserRole.cashier and user.store_id != current_user.store_id:
            raise HTTPException(status_code=403, detail="Not authorized")
    else:
        raise HTTPException(status_code=403, detail="Not authorized")

    # Soft delete - deactivate user instead of hard delete
    user.is_active = False
    user.updated_at = datetime.utcnow()
    db.commit()
    
    # Log the user deactivation action
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=current_user.id,
        action=AUDIT_ACTIONS["USER_DELETE"],
        resource_type="user",
        resource_id=user.id,
        details={
            "target_user_role": user.role,
            "target_user_store_id": user.store_id,
            "deactivation_reason": "soft_delete"
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent")
    )
    
    return {"message": "User deactivated successfully"}
@router.put("/users/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: int,
    user_update: UserUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # Permission checks
    if current_user.role == UserRole.superadmin:
        pass  # Can update all users
    elif current_user.role == UserRole.admin:
        if user.role == UserRole.superadmin:
            raise HTTPException(status_code=403, detail="Not authorized")
        if user.role == UserRole.admin and user.id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized")
        if user.role == UserRole.cashier and user.store_id != current_user.store_id:
            raise HTTPException(status_code=403, detail="Not authorized")
        # Admins cannot change roles to superadmin or admin
        if user_update.role in ["superadmin", "admin"]:
            raise HTTPException(status_code=403, detail="Not authorized to assign this role")
    else:
        if user.id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized")
        # Cashiers cannot change their role or store
        if user_update.role or user_update.store_id:
            raise HTTPException(status_code=403, detail="Not authorized")

    # Update fields
    for field, value in user_update.dict(exclude_unset=True).items():
        if field == "password" and value:
            setattr(user, "password_hash", get_password_hash(value))
        elif field != "password":
            setattr(user, field, value)

    user.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(user)
    
    # Log the user update
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=current_user.id,
        action=AUDIT_ACTIONS["USER_UPDATE"],
        resource_type="user",
        resource_id=user.id,
        details={
            "updated_fields": list(user_update.dict(exclude_unset=True).keys()),
            "old_role": user.role if "role" in user_update.dict(exclude_unset=True) else None,
            "new_role": user_update.role,
            "old_store_id": user.store_id if "store_id" in user_update.dict(exclude_unset=True) else None,
            "new_store_id": user_update.store_id
        },
        ip_address=request.client.host,
        user_agent=request.headers.get("user-agent")
    )
    
    return UserResponse.from_orm(user)
@router.delete("/users/{user_id}/hard")
async def hard_delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # Only superadmin can hard delete users
    if current_user.role != UserRole.superadmin:
        raise HTTPException(status_code=403, detail="Only superadmin can hard delete users")

    # Cannot delete yourself
    if user.id == current_user.id:
        raise HTTPException(status_code=403, detail="Cannot delete your own account")

    # Hard delete the user
    db.delete(user)
    db.commit()
    return {"message": "User permanently deleted successfully"}

@router.get("/users/store/{store_id}", response_model=List[UserResponse])
async def read_users_by_store(
    store_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    # Permission checks
    if current_user.role == UserRole.superadmin:
        pass  # Can view all stores
    elif current_user.role == UserRole.admin:
        if store_id != current_user.store_id:
            raise HTTPException(status_code=403, detail="Not authorized")
    else:
        raise HTTPException(status_code=403, detail="Not authorized")

    users = db.query(User).filter(User.store_id == store_id, User.is_active == True).all()
    return [UserResponse.from_orm(user) for user in users]

# Enhanced Store Management Endpoints

@router.get("/stores", response_model=List[StoreResponse])
async def read_stores(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    query = db.query(Store).filter(Store.is_active == True)

    if current_user.role == UserRole.superadmin:
        stores = query.offset(skip).limit(limit).all()
    else:
        # Non-superadmin users can only see their assigned store
        stores = query.filter(Store.id == current_user.store_id).all()

    return [StoreResponse.from_orm(store) for store in stores]

@router.get("/stores/{store_id}", response_model=StoreResponse)
async def read_store(
    store_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    store = db.query(Store).filter(Store.id == store_id, Store.is_active == True).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store not found")

    # Permission checks
    if current_user.role != UserRole.superadmin and store.id != current_user.store_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    return StoreResponse.from_orm(store)

@router.put("/stores/{store_id}", response_model=StoreResponse)
async def update_store(
    store_id: int,
    store_update: StoreUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    store = db.query(Store).filter(Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store not found")

    # Permission checks
    if current_user.role == UserRole.superadmin:
        pass  # Can update all stores
    elif current_user.role == UserRole.admin:
        if store.id != current_user.store_id:
            raise HTTPException(status_code=403, detail="Not authorized")
    else:
        raise HTTPException(status_code=403, detail="Not authorized")

    # Update fields
    for field, value in store_update.dict(exclude_unset=True).items():
        setattr(store, field, value)

    store.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(store)
    
    # Log the store update action
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=current_user.id,
        action=AUDIT_ACTIONS["UPDATE_STORE"],
        resource_type="store",
        resource_id=store.id,
        details={
            "updated_fields": list(store_update.dict(exclude_unset=True).keys()),
            "store_name": store.name,
            "store_location": store.location
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent")
    )
    
    return StoreResponse.from_orm(store)

@router.delete("/stores/{store_id}")
async def delete_store(
    store_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    if current_user.role != UserRole.superadmin:
        raise HTTPException(status_code=403, detail="Only superadmin can deactivate stores")

    store = db.query(Store).filter(Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store not found")

    # Soft delete - deactivate store instead of hard delete
    store.is_active = False
    store.updated_at = datetime.utcnow()
    db.commit()
    
    # Log the store deactivation action
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=current_user.id,
        action=AUDIT_ACTIONS["DELETE_STORE"],
        resource_type="store",
        resource_id=store.id,
        details={
            "store_name": store.name,
            "store_location": store.location,
            "deactivation_reason": "soft_delete"
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent")
    )
    
    return {"message": "Store deactivated successfully"}


@router.delete("/stores/{store_id}/hard")
async def hard_delete_store_endpoint(
    store_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Hard delete a store and all related records. Only superadmin allowed."""
    if current_user.role != UserRole.superadmin:
        raise HTTPException(status_code=403, detail="Only superadmin can hard delete stores")

    from src.store_utils import hard_delete_store

    # Capture actor id before deletion in case their user row is affected
    actor_id = current_user.id

    # Will raise HTTPException(404) if not found
    result = hard_delete_store(db, store_id)

    # Log the hard delete action using captured actor_id
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=actor_id,
        action=AUDIT_ACTIONS["DELETE_STORE"],
        resource_type="store",
        resource_id=store_id,
        details={
            "store_id": store_id,
            "action": "hard_delete"
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent") if request else None
    )

    return result

@router.get("/stores/{store_id}/users")
async def read_store_users(
    store_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    # Permission checks
    if current_user.role == UserRole.superadmin:
        pass  # Can view all stores
    elif current_user.role == UserRole.admin:
        if store_id != current_user.store_id:
            raise HTTPException(status_code=403, detail="Not authorized")
    else:
        raise HTTPException(status_code=403, detail="Not authorized")

    users = db.query(User).filter(User.store_id == store_id, User.is_active == True).all()
    return users

@router.post("/stores/{store_id}/assign-admin")
async def assign_admin_to_store(
    store_id: int,
    admin_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    if current_user.role != UserRole.superadmin:
        raise HTTPException(status_code=403, detail="Only superadmin can assign admins to stores")

    store = db.query(Store).filter(Store.id == store_id).first()
    if not store:
        raise HTTPException(status_code=404, detail="Store not found")

    admin = db.query(User).filter(User.id == admin_id, User.role == UserRole.admin).first()
    if not admin:
        raise HTTPException(status_code=404, detail="Admin not found")

    admin.store_id = store_id
    admin.updated_at = datetime.utcnow()
    db.commit()
    return {"message": "Admin assigned to store successfully"}