#!/usr/bin/env python3
"""
Test script to verify the sync/initial endpoint works correctly
"""
import os
import sys
import json
from fastapi.testclient import TestClient

# Add the src directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

# Set up test environment
os.environ['DATABASE_URL'] = 'sqlite:///./test_sync.db'
os.environ['SECRET_KEY'] = 'test_secret_key'

from src.main import app
from src.database import get_engine, SessionLocal
from src.models import Base
from sqlalchemy.orm import sessionmaker

# Create test database
engine = get_engine()
Base.metadata.create_all(bind=engine)

# Create test client
client = TestClient(app)

def test_sync_initial_endpoint():
    """Test the /api/sync/initial endpoint"""
    print("🧪 Testing /api/sync/initial endpoint...")

    # Create a test user first (this would normally be done by auth)
    db = SessionLocal()
    try:
        from src.models import User
        from src.auth import get_password_hash

        # Check if test user exists
        test_user = db.query(User).filter(User.username == "testuser").first()
        if not test_user:
            test_user = User(
                username="testuser",
                full_name="Test User",
                password_hash=get_password_hash("testpass"),
                role="admin",
                is_active=True
            )
            db.add(test_user)
            db.commit()
            db.refresh(test_user)

        # Test the endpoint
        headers = {"Authorization": "Bearer test_token"}
        response = client.get("/api/sync/initial", headers=headers)

        print(f"📊 Response status: {response.status_code}")

        if response.status_code == 200:
            data = response.json()
            print("✅ Sync endpoint returned successfully!")
            print(f"📦 Data keys: {list(data.keys())}")

            # Check expected keys
            expected_keys = ['users', 'products', 'stores', 'transactions', 'server_time']
            for key in expected_keys:
                if key in data:
                    print(f"✅ {key}: {len(data[key])} items")
                else:
                    print(f"❌ Missing key: {key}")

            return True
        else:
            print(f"❌ Error: {response.status_code}")
            print(f"Response: {response.text}")
            return False

    except Exception as e:
        print(f"❌ Exception: {e}")
        return False
    finally:
        db.close()

if __name__ == "__main__":
    success = test_sync_initial_endpoint()
    if success:
        print("\n🎉 All tests passed!")
        sys.exit(0)
    else:
        print("\n💥 Tests failed!")
        sys.exit(1)