#!/usr/bin/env python3
"""
Authentication test script for POS and Inventory System
Tests login with admin credentials
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from src.database import SessionLocal
from src.auth import authenticate_user, get_password_hash, verify_password
from src.models import User

def test_auth():
    """Test authentication with admin credentials"""
    db = SessionLocal()

    try:
        print("Testing authentication with username: admin, password: password")

        # Get the user
        user = db.query(User).filter(User.username == "admin").first()
        if not user:
            print("❌ User not found!")
            return

        print(f"Found user: {user.username}")
        print(f"Stored hash: {user.password_hash}")

        # Test password verification directly
        expected_hash = get_password_hash("password")
        print(f"Expected hash for 'password': {expected_hash}")

        is_valid = verify_password("password", user.password_hash)
        print(f"Password verification result: {is_valid}")

        # Test full authentication
        auth_result = authenticate_user(db, "admin", "password")
        print(f"Full authentication result: {auth_result}")

        if auth_result:
            print("✅ Authentication successful!")
        else:
            print("❌ Authentication failed!")

    except Exception as e:
        print(f"Error during authentication test: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    test_auth()