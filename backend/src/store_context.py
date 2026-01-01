from typing import Optional, List
from fastapi import Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from src.database import get_db
from src.models import User, UserRole, Store, UserStore
from src.auth import get_current_active_user

# Sentinel to distinguish between "no value provided" and an explicit None for global view
_UNSET = object()

class StoreContext:
    """Manages store context for multi-store operations"""

    def __init__(self, user: User, current_store_id: Optional[int] | object = _UNSET):
        self.user = user
        # If caller omitted the parameter (i.e., _UNSET), fall back to user's default store_id
        # If caller passed None explicitly, that represents the global view and should be preserved.
        if current_store_id is _UNSET:
            self.current_store_id = user.store_id
        else:
            self.current_store_id = current_store_id
        self._validate_store_access()

    def _validate_store_access(self):
        """Validate that user has access to the current store"""
        if self.user.role == UserRole.superadmin:
            # Superadmin can access any store
            return

        if self.user.role == UserRole.admin:
            # Admin can access assigned stores - we'll check this when switching
            return

        if self.user.role == UserRole.cashier:
            # Cashier can only access their assigned store
            if self.current_store_id != self.user.store_id:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Cashiers can only access their assigned store"
                )

    @property
    def store_id(self) -> Optional[int]:
        """Get current store ID"""
        return self.current_store_id

    @property
    def is_superadmin(self) -> bool:
        """Check if user is superadmin"""
        try:
            role_name = self.user.role.name
        except AttributeError:
            role_name = str(self.user.role)
        return role_name == 'superadmin'

    @property
    def is_admin(self) -> bool:
        """Check if user is admin"""
        try:
            role_name = self.user.role.name
        except AttributeError:
            role_name = str(self.user.role)
        return role_name == 'admin'

    @property
    def is_cashier(self) -> bool:
        """Check if user is cashier"""
        try:
            role_name = self.user.role.name
        except AttributeError:
            role_name = str(self.user.role)
        return role_name == 'cashier'

    def can_access_store(self, store_id: int, db: Optional[Session] = None) -> bool:
        """Check if user can access a specific store"""
        if self.is_superadmin:
            return True

        if self.is_admin:
            # Check assignments if a DB session is provided
            if db is not None:
                assigned = db.query(UserStore).filter(
                    UserStore.user_id == self.user.id,
                    UserStore.store_id == store_id
                ).first()
                return assigned is not None
            # Without DB session, be permissive for backward compatibility
            return True

        if self.is_cashier:
            return store_id == self.user.store_id

        return False

    def get_accessible_stores(self, db: Session) -> List[Store]:
        """Get list of stores user can access"""
        if self.is_superadmin:
            return db.query(Store).filter(Store.is_active == True).all()

        if self.is_admin:
            # Return assigned stores if assignments exist
            assigned = db.query(Store).join(UserStore, Store.id == UserStore.store_id).filter(
                UserStore.user_id == self.user.id,
                Store.is_active == True
            ).all()
            if assigned:
                return assigned
            # No assignments -> return empty list (admins must be explicitly assigned stores)
            return []

        if self.is_cashier and self.user.store_id:
            store = db.query(Store).filter(
                Store.id == self.user.store_id,
                Store.is_active == True
            ).first()
            return [store] if store else []

        return []

    def switch_store(self, store_id: int, db: Session) -> 'StoreContext':
        """Switch to a different store context. Accepts store_id==0 to mean "All Stores" (global view)."""
        # Special case: store_id==0 means global/all-stores view
        if store_id == 0:
            # Only superadmins may switch to global view
            if not self.is_superadmin:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="You do not have access to view all stores"
                )
            # Return a context with no specific store (global)
            return StoreContext(self.user, None)

        if not self.can_access_store(store_id, db):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not have access to this store"
            )

        # Verify store exists and is active
        store = db.query(Store).filter(
            Store.id == store_id,
            Store.is_active == True
        ).first()

        if not store:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Store not found or inactive"
            )

        return StoreContext(self.user, store_id)

def get_store_context(
    request: Request,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
) -> StoreContext:
    """Dependency to get current store context from request headers or user default"""
    # Try to get store_id from header first
    store_id_header = request.headers.get('X-Store-ID')

    # Diagnostic logging to help debug 403s related to store access
    try:
        # Note: request.client may be None in some test contexts
        client_ip = request.client.host if request.client else 'unknown'
    except Exception:
        client_ip = 'unknown'
    debug_info = f"get_store_context: user_id={getattr(current_user, 'id', None)} user_store_id={getattr(current_user, 'store_id', None)} header={store_id_header} client_ip={client_ip} path={request.url.path}"
    print(debug_info)

    if store_id_header:
        try:
            current_store_id = int(store_id_header)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid X-Store-ID header"
            )
        return StoreContext(current_user, current_store_id)

    # No explicit header -> fall back to user's persisted current store
    return StoreContext(current_user)

def require_store_access(store_context: StoreContext = Depends(get_store_context)):
    """Dependency that ensures user has access to current store context"""
    return store_context