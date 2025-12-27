from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime
from src.database import get_db
from src.auth import get_current_active_user
from src.models import User, UserRole, AuditLog
from src.audit_service import AuditService
from src.store_context import StoreContext, require_store_access
from src.schemas import AuditLogResponse, AuditLogListResponse

router = APIRouter()

@router.get("/audit-logs", response_model=AuditLogListResponse)
async def get_audit_logs(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    user_id: Optional[int] = None,
    action: Optional[str] = None,
    resource_type: Optional[str] = None,
    start_date: Optional[datetime] = None,
    end_date: Optional[datetime] = None,
    store_context: StoreContext = Depends(require_store_access),
    db: Session = Depends(get_db)
):
    """Get audit logs filtered by store context"""
    # Only superadmin and admin can view audit logs
    if store_context.user.role not in [UserRole.superadmin, UserRole.admin]:
        raise HTTPException(status_code=403, detail="Not authorized to view audit logs")

    audit_service = AuditService(db)

    # Filter by store for non-superadmin users
    store_id_filter = None
    if not store_context.is_superadmin:
        store_id_filter = store_context.store_id

    # Get the filtered logs
    logs = audit_service.get_audit_logs(
        user_id=user_id,
        action=action,
        resource_type=resource_type,
        start_date=start_date,
        end_date=end_date,
        store_id=store_id_filter,
        limit=limit,
        offset=skip
    )

    # Count total matching logs for pagination
    total_count = audit_service.get_audit_logs_count(
        user_id=user_id,
        action=action,
        resource_type=resource_type,
        start_date=start_date,
        end_date=end_date,
        store_id=store_id_filter,
    )

    # Logs are returned as dicts from AuditService; validate/convert them with Pydantic
    validated_logs = [AuditLogResponse.model_validate(log) for log in logs]

    return {
        'logs': validated_logs,
        'total_count': total_count,
    }