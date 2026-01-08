#!/usr/bin/env python3
"""
Database inspection script for audit logs
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from src.database import SessionLocal
from src.models import AuditLog

def inspect_audit_logs():
    """Inspect audit logs in database"""
    db = SessionLocal()

    try:
        # Get all audit logs with user relationship
        audit_logs = db.query(AuditLog).order_by(AuditLog.created_at.desc()).limit(20).all()

        print(f"Found {len(audit_logs)} recent audit logs in database:")
        for log in audit_logs:
            username = log.user.username if log.user else "Unknown"
            print(f"ID: {log.id}")
            print(f"User ID: {log.user_id}")
            print(f"Username: {username}")
            print(f"Action: {log.action}")
            print(f"Resource Type: {log.resource_type}")
            print(f"Resource ID: {log.resource_id}")
            print(f"Store ID: {log.store_id}")
            print(f"Created At: {log.created_at}")
            print("---")

        if not audit_logs:
            print("No audit logs found in database!")

        # Also check total count
        total_count = db.query(AuditLog).count()
        print(f"Total audit logs in database: {total_count}")

        # Check for audit logs with store_id not None
        logs_with_store = db.query(AuditLog).filter(AuditLog.store_id.isnot(None)).count()
        print(f"Audit logs with store_id set: {logs_with_store}")

        # Check for different resource types
        from sqlalchemy import func
        resource_counts = db.query(AuditLog.resource_type, func.count(AuditLog.id)).group_by(AuditLog.resource_type).all()
        print("Audit logs by resource type:")
        for resource_type, count in resource_counts:
            print(f"  {resource_type}: {count}")

    except Exception as e:
        print(f"Error inspecting audit logs: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    inspect_audit_logs()