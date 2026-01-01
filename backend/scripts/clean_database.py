"""
Clean PostgreSQL database for production deployment.
Removes all data except the superadmin user.
"""
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from src.database import SessionLocal
from src.models import (User, Product, Store, Sale, SaleItem, AnalyticsEvent, Change,
                        AuditLog, InventoryLog, StoreSettings, UserSettings, SystemSettings)
from sqlalchemy import text

def clean_database():
    """Clean database keeping only superadmin user."""
    db = SessionLocal()
    
    try:
        print("🧹 Starting database cleanup...")
        
        # Get superadmin and default store IDs
        superadmin = db.query(User).filter(User.username == 'superadmin').first()
        if not superadmin:
            print("❌ Error: Superadmin user not found! Run init_db.py first.")
            return
        
        default_store = db.query(Store).filter(Store.name == 'Default Store').first()
        
        superadmin_id = superadmin.id
        default_store_id = default_store.id if default_store else None
        
        print(f"  Keeping: superadmin (ID: {superadmin_id})")
        if default_store_id:
            print(f"  Keeping: Default Store (ID: {default_store_id})")
        
        # Use raw SQL for efficient cascade deletion
        print("\n  - Truncating tables (keeping superadmin)...")
        
        # Delete in dependency order using raw SQL
        db.execute(text("DELETE FROM sale_items"))
        db.execute(text("DELETE FROM sales"))
        db.execute(text("DELETE FROM inventory_logs"))
        db.execute(text("DELETE FROM analytics_events"))
        db.execute(text("DELETE FROM audit_logs"))
        db.execute(text("DELETE FROM changes"))
        db.execute(text("DELETE FROM products"))
        db.execute(text("DELETE FROM store_settings"))
        db.execute(text("DELETE FROM user_settings WHERE user_id != :superadmin_id"), {"superadmin_id": superadmin_id})
        db.execute(text("DELETE FROM user_stores WHERE user_id != :superadmin_id"), {"superadmin_id": superadmin_id})
        
        # Update foreign keys to NULL before deletion
        if default_store_id:
            db.execute(text("UPDATE users SET store_id = :default_store WHERE id = :superadmin_id"), 
                      {"default_store": default_store_id, "superadmin_id": superadmin_id})
            db.execute(text("UPDATE stores SET created_by = :superadmin_id WHERE id = :default_store"), 
                      {"superadmin_id": superadmin_id, "default_store": default_store_id})
            db.execute(text("DELETE FROM stores WHERE id != :default_store"), {"default_store": default_store_id})
        else:
            db.execute(text("UPDATE users SET store_id = NULL WHERE id != :superadmin_id"), {"superadmin_id": superadmin_id})
            db.execute(text("DELETE FROM stores"))
        
        db.execute(text("DELETE FROM users WHERE id != :superadmin_id"), {"superadmin_id": superadmin_id})
        
        # Commit deletions
        db.commit()
        
        print("\n✅ Database cleaned successfully!")
        
        # Reset sequences for clean IDs in production
        print("\n🔄 Resetting ID sequences...")
        try:
            db.execute(text("ALTER SEQUENCE users_id_seq RESTART WITH 2"))
            db.execute(text("ALTER SEQUENCE products_id_seq RESTART WITH 1"))
            db.execute(text("ALTER SEQUENCE stores_id_seq RESTART WITH 2"))
            db.execute(text("ALTER SEQUENCE sales_id_seq RESTART WITH 1"))
            db.execute(text("ALTER SEQUENCE sale_items_id_seq RESTART WITH 1"))
            db.commit()
            print("✅ Sequences reset successfully!")
        except Exception as e:
            print(f"⚠️  Warning: Could not reset sequences (might be SQLite): {e}")
        
        # Verify superadmin still exists
        superadmin = db.query(User).filter(User.username == 'superadmin').first()
        if superadmin:
            print(f"\n✅ Superadmin user verified: {superadmin.username} (ID: {superadmin.id})")
        else:
            print("\n⚠️  WARNING: Superadmin user not found! Run init_db.py to create it.")
        
        # Show remaining data
        print("\n📊 Remaining data:")
        print(f"   Users: {db.query(User).count()}")
        print(f"   Stores: {db.query(Store).count()}")
        print(f"   Products: {db.query(Product).count()}")
        print(f"   Sales: {db.query(Sale).count()}")
        
    except Exception as e:
        db.rollback()
        print(f"\n❌ Error during cleanup: {e}")
        raise
    finally:
        db.close()

if __name__ == '__main__':
    print("⚠️  WARNING: This will delete ALL data except the superadmin user!")
    response = input("Are you sure you want to continue? (yes/no): ")
    
    if response.lower() in ['yes', 'y']:
        clean_database()
    else:
        print("❌ Cleanup cancelled.")
