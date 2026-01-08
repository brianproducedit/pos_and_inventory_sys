#!/usr/bin/env python3
"""
Database cleanup utility to check for duplicates and inconsistencies.
"""
import sys
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import func
from src.database import SessionLocal
from src.models import Product, User, Store


def check_duplicate_products():
    """Find products with duplicate names in the same store."""
    db = SessionLocal()
    try:
        print("\n🔍 Checking for duplicate products...")
        
        # Find duplicate product names within the same store
        duplicates = (
            db.query(
                Product.name,
                Product.store_id,
                func.count(Product.id).label('count')
            )
            .filter(Product.is_active == True)
            .group_by(Product.name, Product.store_id)
            .having(func.count(Product.id) > 1)
            .all()
        )
        
        if not duplicates:
            print("  ✅ No duplicate products found")
            return
        
        print(f"  ⚠️ Found {len(duplicates)} duplicate product groups:")
        for name, store_id, count in duplicates:
            print(f"    - '{name}' in store {store_id}: {count} copies")
            
            # Show the duplicate products
            products = (
                db.query(Product)
                .filter(Product.name == name, Product.store_id == store_id)
                .all()
            )
            for p in products:
                print(f"      • id={p.id}, created={p.created_at}, stock={p.stock_quantity}")
    finally:
        db.close()


def check_duplicate_users():
    """Find users with duplicate usernames."""
    db = SessionLocal()
    try:
        print("\n🔍 Checking for duplicate users...")
        
        # Find duplicate usernames
        duplicates = (
            db.query(
                User.username,
                func.count(User.id).label('count')
            )
            .filter(User.is_active == True)
            .group_by(User.username)
            .having(func.count(User.id) > 1)
            .all()
        )
        
        if not duplicates:
            print("  ✅ No duplicate users found")
            return
        
        print(f"  ⚠️ Found {len(duplicates)} duplicate usernames:")
        for username, count in duplicates:
            print(f"    - '{username}': {count} copies")
            
            # Show the duplicate users
            users = db.query(User).filter(User.username == username).all()
            for u in users:
                print(f"      • id={u.id}, role={u.role}, store_id={u.store_id}, created={u.created_at}")
    finally:
        db.close()


def check_orphaned_products():
    """Find products referencing non-existent stores."""
    db = SessionLocal()
    try:
        print("\n🔍 Checking for orphaned products...")
        
        orphaned = (
            db.query(Product)
            .filter(Product.store_id.isnot(None))
            .filter(~Product.store_id.in_(db.query(Store.id)))
            .all()
        )
        
        if not orphaned:
            print("  ✅ No orphaned products found")
            return
        
        print(f"  ⚠️ Found {len(orphaned)} orphaned products:")
        for p in orphaned:
            print(f"    - id={p.id}, name='{p.name}', references store_id={p.store_id} (doesn't exist)")
    finally:
        db.close()


def check_orphaned_users():
    """Find users referencing non-existent stores."""
    db = SessionLocal()
    try:
        print("\n🔍 Checking for orphaned users...")
        
        orphaned = (
            db.query(User)
            .filter(User.store_id.isnot(None))
            .filter(~User.store_id.in_(db.query(Store.id)))
            .all()
        )
        
        if not orphaned:
            print("  ✅ No orphaned users found")
            return
        
        print(f"  ⚠️ Found {len(orphaned)} orphaned users:")
        for u in orphaned:
            print(f"    - id={u.id}, username='{u.username}', references store_id={u.store_id} (doesn't exist)")
    finally:
        db.close()


def show_database_stats():
    """Show overall database statistics."""
    db = SessionLocal()
    try:
        print("\n📊 Database Statistics:")
        
        total_products = db.query(Product).count()
        active_products = db.query(Product).filter(Product.is_active == True).count()
        print(f"  Products: {total_products} total, {active_products} active")
        
        total_users = db.query(User).count()
        active_users = db.query(User).filter(User.is_active == True).count()
        print(f"  Users: {total_users} total, {active_users} active")
        
        total_stores = db.query(Store).count()
        active_stores = db.query(Store).filter(Store.is_active == True).count()
        print(f"  Stores: {total_stores} total, {active_stores} active")
        
        # Show stores
        stores = db.query(Store).filter(Store.is_active == True).all()
        print(f"\n  Active Stores:")
        for s in stores:
            product_count = db.query(Product).filter(Product.store_id == s.id).count()
            user_count = db.query(User).filter(User.store_id == s.id).count()
            print(f"    - id={s.id}, name='{s.name}', products={product_count}, users={user_count}")
    finally:
        db.close()


def main():
    """Run all database checks."""
    print("=" * 60)
    print("🧹 Database Cleanup Check")
    print("=" * 60)
    
    show_database_stats()
    check_duplicate_products()
    check_duplicate_users()
    check_orphaned_products()
    check_orphaned_users()
    
    print("\n" + "=" * 60)
    print("✅ Check complete!")
    print("=" * 60)


if __name__ == '__main__':
    main()
