#!/usr/bin/env python3
"""
Check product sales script
Shows if a product has been sold
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from src.database import SessionLocal
from src.models import Product, SaleItem

def check_product_sales(product_id):
    """Check if a product has been sold"""
    db = SessionLocal()

    try:
        # Check if product exists
        product = db.query(Product).filter(Product.id == product_id).first()
        if not product:
            print(f"Product {product_id} not found")
            return

        print(f"Product: {product.name} (ID: {product.id})")

        # Check for sale items
        sale_items = db.query(SaleItem).filter(SaleItem.product_id == product_id).all()
        print(f"Found {len(sale_items)} sale items for this product")

        if sale_items:
            print("Sale items:")
            for item in sale_items:
                print(f"  Sale Item ID: {item.id}, Sale ID: {item.sale_id}, Quantity: {item.quantity}")
        else:
            print("No sales found - safe to delete")

    except Exception as e:
        print(f"Error checking product sales: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    check_product_sales(4)