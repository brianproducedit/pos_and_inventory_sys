#!/usr/bin/env python3
"""
Check all products for sales
Shows which products can be safely deleted
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from src.database import SessionLocal
from src.models import Product, SaleItem

def check_all_products():
    """Check all products for sales"""
    db = SessionLocal()

    try:
        products = db.query(Product).all()

        print("Product deletion status:")
        print("=" * 50)

        for product in products:
            sale_count = db.query(SaleItem).filter(SaleItem.product_id == product.id).count()
            status = "❌ Cannot delete (has sales)" if sale_count > 0 else "✅ Can delete (no sales)"
            print(f"ID {product.id}: {product.name} - {status} ({sale_count} sales)")

    except Exception as e:
        print(f"Error checking products: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    check_all_products()