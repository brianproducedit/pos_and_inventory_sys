#!/usr/bin/env python3
"""
Database inspection script for stores
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from src.database import SessionLocal
from src.models import Store

def inspect_stores():
    """Inspect stores in database"""
    db = SessionLocal()

    try:
        # Get all stores
        stores = db.query(Store).all()

        print(f"Found {len(stores)} stores in database:")
        for store in stores:
            print(f"ID: {store.id}")
            print(f"Name: {store.name}")
            print(f"Location: {store.location}")
            print(f"Is Active: {store.is_active}")
            print(f"Created By: {store.created_by}")
            print("---")

        if not stores:
            print("No stores found in database!")

    except Exception as e:
        print(f"Error inspecting stores: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    inspect_stores()