#!/usr/bin/env python3
"""
Quick script to check for duplicate stores in PostgreSQL database.
"""
import os
import sys
from sqlalchemy import create_engine, text

# Use the same database URL as the application
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgresql@localhost:5432/pos_db"
)

def check_stores():
    """Check for stores in the database."""
    engine = create_engine(DATABASE_URL)
    
    with engine.connect() as conn:
        # Get all stores
        result = conn.execute(text("""
            SELECT id, name, location, is_active, created_at
            FROM stores
            ORDER BY id
        """))
        
        stores = result.fetchall()
        
        print(f"\n{'='*80}")
        print(f"STORES IN DATABASE ({len(stores)} total)")
        print(f"{'='*80}\n")
        
        for store in stores:
            print(f"ID: {store[0]}")
            print(f"Name: {store[1]}")
            print(f"Location: {store[2]}")
            print(f"Active: {store[3]}")
            print(f"Created: {store[4]}")
            print("-" * 80)
        
        # Check for duplicate names
        result = conn.execute(text("""
            SELECT name, COUNT(*) as count
            FROM stores
            GROUP BY name
            HAVING COUNT(*) > 1
        """))
        
        duplicates = result.fetchall()
        
        if duplicates:
            print(f"\n⚠️  DUPLICATE STORE NAMES FOUND:")
            for dup in duplicates:
                print(f"  - '{dup[0]}' appears {dup[1]} times")
        else:
            print(f"\n✅ No duplicate store names found")

if __name__ == "__main__":
    try:
        check_stores()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
