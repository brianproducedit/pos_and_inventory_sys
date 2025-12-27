import os
import secrets
from src.database import SessionLocal
from src.models import User, UserRole
from src.auth import get_password_hash


def create_admin_user():
    """Create or update the default superadmin user. Idempotent."""
    db = SessionLocal()
    try:
        default_username = os.getenv('DEFAULT_SUPERADMIN_USERNAME', 'superadmin')
        default_password = os.getenv('DEFAULT_SUPERADMIN_PASSWORD')
        generated_password = False
        if not default_password:
            generated_password = True
            default_password = secrets.token_urlsafe(12)
            print("No DEFAULT_SUPERADMIN_PASSWORD set; generated a temporary password for 'superadmin'. Please set DEFAULT_SUPERADMIN_PASSWORD in .env for predictable defaults.")
            print(f"Generated temporary password: {default_password}")

        existing_admin = db.query(User).filter(User.username == default_username).first()
        if existing_admin:
            existing_admin.password_hash = get_password_hash(default_password)
            existing_admin.role = UserRole.superadmin
            existing_admin.must_change_password = True
            db.commit()
            print("Superadmin credentials updated successfully!")
        else:
            admin_user = User(
                username=default_username,
                password_hash=get_password_hash(default_password),
                role=UserRole.superadmin,
                must_change_password=True,
            )
            db.add(admin_user)
            db.commit()
            print("Superadmin user created successfully!")

    except Exception as e:
        print(f"Error creating/updating admin user: {e}")
        db.rollback()
    finally:
        db.close()