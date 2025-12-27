#!/usr/bin/env python3
"""
Database migration script
Adds is_active column to products table
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from src.database import SQLALCHEMY_DATABASE_URL

def migrate_products_table():
    """Add is_active column to products table"""
    engine = create_engine(SQLALCHEMY_DATABASE_URL)

    try:
        with engine.connect() as conn:
            # Check if column already exists
            result = conn.execute(text("PRAGMA table_info(products)"))
            columns = [row[1] for row in result.fetchall()]

            if 'is_active' not in columns:
                print("Adding is_active column to products table...")
                # For SQLite, we need to recreate the table
                conn.execute(text("""
                    ALTER TABLE products ADD COLUMN is_active BOOLEAN DEFAULT 1
                """))
                print("✅ Migration completed successfully!")
            else:
                print("✅ is_active column already exists")

            # Set all existing products to active
            conn.execute(text("UPDATE products SET is_active = 1 WHERE is_active IS NULL"))
            conn.commit()

    except Exception as e:
        print(f"❌ Migration failed: {e}")
        raise

if __name__ == "__main__":
    migrate_products_table()