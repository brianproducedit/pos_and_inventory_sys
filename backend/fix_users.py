#!/usr/bin/env python3
"""
Fix is_active field for existing users
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from src.database import SessionLocal
from src.models import User

def fix_user_active_status():
    """Set is_active to True for all users where it's NULL"""
    db = SessionLocal()

    try:
        # Find users with NULL is_active
        users_to_fix = db.query(User).filter(User.is_active.is_(None)).all()

        if not users_to_fix:
            print("No users found with NULL is_active field.")
            return

        print(f"Found {len(users_to_fix)} users with NULL is_active. Fixing...")

        for user in users_to_fix:
            user.is_active = True
            print(f"Fixed user: {user.username}")

        db.commit()
        print("All users fixed successfully!")

    except Exception as e:
        print(f"Error fixing users: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    fix_user_active_status()