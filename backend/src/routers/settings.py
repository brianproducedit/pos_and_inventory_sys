from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from ..database import get_db
from ..models import StoreSettings, UserSettings, SystemSettings, User, Store
from ..auth import get_current_active_user
from ..audit_service import AuditService, AUDIT_ACTIONS
from pydantic import BaseModel
from typing import Optional

router = APIRouter()

# Pydantic models for request/response
class StoreSettingsBase(BaseModel):
    business_name: Optional[str] = None
    address: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    tax_number: Optional[str] = None
    receipt_footer: Optional[str] = None

class UserSettingsBase(BaseModel):
    theme: str = 'light'
    language: str = 'en'
    notifications_enabled: bool = True

class SystemSettingsBase(BaseModel):
    key: str
    value: Optional[str] = None

# Store Settings Endpoints
@router.get("/store")
async def get_store_settings(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Get settings for the current user's store"""
    if not current_user.store_id:
        raise HTTPException(status_code=400, detail="User not assigned to a store")

    settings = db.query(StoreSettings).filter(StoreSettings.store_id == current_user.store_id).first()
    if not settings:
        # Return default settings if none exist
        return StoreSettingsBase()

    return {
        "business_name": settings.business_name,
        "address": settings.address,
        "phone": settings.phone,
        "email": settings.email,
        "tax_number": settings.tax_number,
        "receipt_footer": settings.receipt_footer
    }

@router.put("/store")
async def update_store_settings(
    settings_data: StoreSettingsBase,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Update settings for the current user's store (admin/superadmin only)"""
    if current_user.role.value not in ['admin', 'superadmin']:
        raise HTTPException(status_code=403, detail="Not authorized to update store settings")

    if not current_user.store_id and current_user.role.value != 'superadmin':
        raise HTTPException(status_code=400, detail="User not assigned to a store")

    store_id = current_user.store_id

    # For superadmin, they might need to specify store_id, but for now use their assigned store
    if not store_id:
        raise HTTPException(status_code=400, detail="Superadmin must specify store context")

    settings = db.query(StoreSettings).filter(StoreSettings.store_id == store_id).first()

    if not settings:
        # Create new settings
        settings = StoreSettings(store_id=store_id)

    # Update fields
    for field, value in settings_data.dict(exclude_unset=True).items():
        setattr(settings, field, value)

    db.add(settings)
    db.commit()
    db.refresh(settings)
    
    # Log the store settings update action
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=current_user.id,
        action=AUDIT_ACTIONS["UPDATE_STORE_SETTINGS"],
        resource_type="store_settings",
        resource_id=settings.id,
        details={
            "updated_fields": list(settings_data.dict(exclude_unset=True).keys()),
            "store_id": store_id
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent")
    )

    return {"message": "Store settings updated successfully"}

# User Settings Endpoints
@router.get("/user")
async def get_user_settings(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Get settings for the current user"""
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    if not settings:
        # Return default settings if none exist
        return UserSettingsBase()

    return {
        "theme": settings.theme,
        "language": settings.language,
        "notifications_enabled": settings.notifications_enabled
    }

@router.put("/user")
async def update_user_settings(
    settings_data: UserSettingsBase,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Update settings for the current user"""
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()

    if not settings:
        # Create new settings
        settings = UserSettings(user_id=current_user.id)

    # Update fields
    for field, value in settings_data.dict().items():
        setattr(settings, field, value)

    db.add(settings)
    db.commit()
    db.refresh(settings)
    
    # Log the user settings update action
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=current_user.id,
        action=AUDIT_ACTIONS["UPDATE_USER_SETTINGS"],
        resource_type="user_settings",
        resource_id=settings.id,
        details={
            "updated_fields": list(settings_data.dict().keys())
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent")
    )

    return {"message": "User settings updated successfully"}

# System Settings Endpoints (Superadmin only)
@router.get("/system")
async def get_system_settings(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Get all system settings (superadmin only)"""
    if current_user.role.value != 'superadmin':
        raise HTTPException(status_code=403, detail="Only superadmin can access system settings")

    settings = db.query(SystemSettings).all()
    return {setting.key: setting.value for setting in settings}

@router.put("/system")
async def update_system_setting(
    setting_data: SystemSettingsBase,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Update a system setting (superadmin only)"""
    if current_user.role.value != 'superadmin':
        raise HTTPException(status_code=403, detail="Only superadmin can update system settings")

    setting = db.query(SystemSettings).filter(SystemSettings.key == setting_data.key).first()

    if not setting:
        # Create new system setting
        setting = SystemSettings(key=setting_data.key, value=setting_data.value)
    else:
        setting.value = setting_data.value

    db.add(setting)
    db.commit()
    db.refresh(setting)
    
    # Log the system setting update action
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=current_user.id,
        action=AUDIT_ACTIONS["UPDATE_SYSTEM_SETTINGS"],
        resource_type="system_settings",
        resource_id=setting.id,
        details={
            "setting_key": setting_data.key,
            "old_value": setting.value if setting else None,
            "new_value": setting_data.value
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent")
    )

    return {"message": f"System setting '{setting_data.key}' updated successfully"}

@router.get("/system/{key}")
async def get_system_setting(
    key: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Get a specific system setting (superadmin only)"""
    if current_user.role.value != 'superadmin':
        raise HTTPException(status_code=403, detail="Only superadmin can access system settings")

    setting = db.query(SystemSettings).filter(SystemSettings.key == key).first()
    if not setting:
        raise HTTPException(status_code=404, detail="System setting not found")

    return {"key": setting.key, "value": setting.value}