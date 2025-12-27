from sqlalchemy.orm import Session
from src.models import AuditLog
from typing import Optional
import json
from datetime import datetime

class AuditService:
    def __init__(self, db: Session):
        self.db = db

    def log_activity(
        self,
        user_id: Optional[int],
        action: str,
        resource_type: str,
        resource_id: Optional[int] = None,
        details: Optional[dict] = None,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None,
        store_id: Optional[int] = None
    ):
        """Log user activity for audit purposes"""
        audit_log = AuditLog(
            user_id=user_id,
            store_id=store_id,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            details=json.dumps(details) if details else None,
            ip_address=ip_address,
            user_agent=user_agent
        )

        self.db.add(audit_log)
        self.db.commit()

    def get_audit_logs(
        self,
        user_id: Optional[int] = None,
        action: Optional[str] = None,
        resource_type: Optional[str] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        store_id: Optional[int] = None,
        limit: int = 100,
        offset: int = 0
    ):
        """Retrieve audit logs with optional filtering"""
        from sqlalchemy import desc, and_

        query = self.db.query(AuditLog)

        # Always join with user to get username
        query = query.join(AuditLog.user, isouter=True)

        if user_id is not None:
            query = query.filter(AuditLog.user_id == user_id)
        if action:
            query = query.filter(AuditLog.action == action)
        if resource_type:
            query = query.filter(AuditLog.resource_type == resource_type)
        if start_date:
            query = query.filter(AuditLog.created_at >= start_date)
        if end_date:
            query = query.filter(AuditLog.created_at <= end_date)
        if store_id is not None:
            query = query.filter(AuditLog.store_id == store_id)

        logs = query.order_by(desc(AuditLog.created_at)).offset(offset).limit(limit).all()

        # Convert to dictionaries
        result = []
        for log in logs:
            log_dict = {
                'id': log.id,
                'user_id': log.user_id,
                'store_id': log.store_id,
                'action': log.action,
                'entity_type': log.resource_type,
                'entity_id': log.resource_id,
                'details': json.loads(log.details) if log.details else None,
                'ip_address': log.ip_address,
                'user_agent': log.user_agent,
                'timestamp': log.created_at,
            }
            result.append(log_dict)

        return result

    def get_audit_logs_count(
        self,
        user_id: Optional[int] = None,
        action: Optional[str] = None,
        resource_type: Optional[str] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        store_id: Optional[int] = None
    ):
        """Get total count of audit logs with optional filtering"""
        from sqlalchemy import func

        query = self.db.query(func.count(AuditLog.id))

        # Always join with user to get username
        query = query.join(AuditLog.user, isouter=True)

        if user_id is not None:
            query = query.filter(AuditLog.user_id == user_id)
        if action:
            query = query.filter(AuditLog.action == action)
        if resource_type:
            query = query.filter(AuditLog.resource_type == resource_type)
        if start_date:
            query = query.filter(AuditLog.created_at >= start_date)
        if end_date:
            query = query.filter(AuditLog.created_at <= end_date)
        if store_id is not None:
            query = query.filter(AuditLog.store_id == store_id)

        return query.scalar()

# Common audit actions
AUDIT_ACTIONS = {
    # User management
    'CREATE_USER': 'CREATE_USER',
    'UPDATE_USER': 'UPDATE_USER',
    'DELETE_USER': 'DELETE_USER',
    'DEACTIVATE_USER': 'DEACTIVATE_USER',
    'ACTIVATE_USER': 'ACTIVATE_USER',
    'CHANGE_PASSWORD': 'CHANGE_PASSWORD',

    # Backwards-compatible aliases (some routers used different keys)
    'USER_UPDATE': 'UPDATE_USER',
    'USER_DELETE': 'DELETE_USER',

    # Store management
    'CREATE_STORE': 'CREATE_STORE',
    'UPDATE_STORE': 'UPDATE_STORE',
    'DELETE_STORE': 'DELETE_STORE',
    'ASSIGN_ADMIN': 'ASSIGN_ADMIN',
    'ASSIGN_STORE': 'ASSIGN_STORE',

    # Product management
    'CREATE_PRODUCT': 'CREATE_PRODUCT',
    'UPDATE_PRODUCT': 'UPDATE_PRODUCT',
    'DELETE_PRODUCT': 'DELETE_PRODUCT',

    # Sales
    'CREATE_SALE': 'CREATE_SALE',
    'VOID_SALE': 'VOID_SALE',

    # Settings
    'UPDATE_STORE_SETTINGS': 'UPDATE_STORE_SETTINGS',
    'UPDATE_USER_SETTINGS': 'UPDATE_USER_SETTINGS',
    'UPDATE_SYSTEM_SETTINGS': 'UPDATE_SYSTEM_SETTINGS',

    # Authentication
    'LOGIN': 'LOGIN',
    'LOGOUT': 'LOGOUT',
    'FAILED_LOGIN': 'FAILED_LOGIN',
}