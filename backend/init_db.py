#!/usr/bin/env python3
"""
Database initialization script for POS and Inventory System
Creates default admin user and sample data
"""

import sys
import os
import secrets
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from src.database import SessionLocal, engine
from src.models import User, UserRole
from src.auth import get_password_hash

def create_admin_user():
    """Create default admin user"""
    db = SessionLocal()

    try:
        # Determine default username/password (can be overridden with env vars)
        default_username = os.getenv('DEFAULT_SUPERADMIN_USERNAME', 'superadmin')
        default_password = os.getenv('DEFAULT_SUPERADMIN_PASSWORD')
        generated_password = False
        if not default_password:
            # No default password provided in env; generate a secure temporary password.
            generated_password = True
            default_password = secrets.token_urlsafe(12)
            print("No DEFAULT_SUPERADMIN_PASSWORD set; generated a temporary password for 'superadmin'. Please set DEFAULT_SUPERADMIN_PASSWORD in .env for predictable defaults.")
            print(f"Generated temporary password: {default_password}")

        # Check if admin user already exists
        existing_admin = db.query(User).filter(User.username == default_username).first()

        if existing_admin:
            print("Superadmin user already exists - updating credentials")

            # Update the password, role and must_change flag to ensure it's correct
            existing_admin.password_hash = get_password_hash(default_password)
            existing_admin.role = UserRole.superadmin
            existing_admin.must_change_password = True
            db.commit()
            print("Superadmin credentials updated successfully!")
        else:
            # Create admin user
            admin_user = User(
                username=default_username,
                password_hash=get_password_hash(default_password),
                role=UserRole.superadmin,
                must_change_password=True
            )
            db.add(admin_user)
            db.commit()
            print("Superadmin user created successfully!")

        print(f"Username: {default_username}")
        print("Note: default credentials should be changed on first login or via environment variables.")

    except Exception as e:
        print(f"Error creating/updating admin user: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    print("Initializing database...")
    create_admin_user()
    print("Database initialization complete!")