#!/usr/bin/env python3
"""
Reset superadmin password
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from src.database import SessionLocal
from src.auth import get_password_hash
from src.models import User

def reset_superadmin_password():
    """Reset superadmin password"""
    db = SessionLocal()

    try:
        superadmin = db.query(User).filter(User.username == 'superadmin').first()
        if superadmin:
            new_password = 'password'
            superadmin.password_hash = get_password_hash(new_password)
            db.commit()
            print(f"Superadmin password reset to: {new_password}")
        else:
            print("Superadmin user not found")

    except Exception as e:
        print(f"Error resetting password: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    reset_superadmin_password()