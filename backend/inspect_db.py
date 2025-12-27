#!/usr/bin/env python3
"""
Database inspection script for POS and Inventory System
Shows current users and their details
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from src.database import SessionLocal
from src.models import User, UserRole

def inspect_database():
    """Inspect database contents"""
    db = SessionLocal()

    try:
        # Get all users
        users = db.query(User).all()

        print(f"Found {len(users)} users in database:")
        for user in users:
            print(f"ID: {user.id}")
            print(f"Username: {user.username}")
            print(f"Role: {user.role}")
            print(f"Password Hash: {user.password_hash[:20]}...")
            print("---")

        if not users:
            print("No users found in database!")

    except Exception as e:
        print(f"Error inspecting database: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    inspect_database()