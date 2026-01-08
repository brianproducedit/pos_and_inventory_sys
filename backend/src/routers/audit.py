from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime
from src.database import get_db
from src.auth import get_current_active_user
from src.models import User, UserRole, AuditLog
from src.audit_service import AuditService
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
    store_id: Optional[int] = None,
    current_user = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get audit logs with optional filtering by store"""
    # Only superadmin and admin can view audit logs
    if current_user.role not in [UserRole.superadmin, UserRole.admin]:
        raise HTTPException(status_code=403, detail="Not authorized to view audit logs")

    audit_service = AuditService(db)

    # For audit logs, don't filter by store - show system-wide logs to authorized users
    # (Audit logs are administrative and should be visible system-wide)
    logs = audit_service.get_audit_logs(
        user_id=user_id,
        action=action,
        resource_type=resource_type,
        start_date=start_date,
        end_date=end_date,
        store_id=None,  # Don't filter by store for audit logs
        limit=limit,
        offset=skip
    )

    # Count total matching logs
    total_count = audit_service.get_audit_logs_count(
        user_id=user_id,
        action=action,
        resource_type=resource_type,
        start_date=start_date,
        end_date=end_date,
        store_id=store_id,
    )

    # Logs are returned as dicts from AuditService; validate/convert them with Pydantic
    validated_logs = [AuditLogResponse.model_validate(log) for log in logs]

    return {
        'logs': validated_logs,
        'total_count': total_count,
    }