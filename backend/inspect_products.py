#!/usr/bin/env python3
"""
Database inspection script for products
Shows current products and their details
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from src.database import SessionLocal
from src.models import Product, User

def inspect_products():
    """Inspect products in database"""
    db = SessionLocal()

    try:
        # Get all products
        products = db.query(Product).all()
        print(f"Found {len(products)} products in database:")

        for product in products:
            print(f"ID: {product.id}")
            print(f"Name: {product.name}")
            print(f"Price: {product.price}")
            print(f"Stock: {product.stock_quantity}")
            print(f"Store ID: {product.store_id}")
            print("---")

        # Check admin user
        admin = db.query(User).filter(User.username == "admin").first()
        if admin:
            print(f"Admin user store_id: {admin.store_id}")
            print(f"Admin user role: {admin.role}")
        else:
            print("Admin user not found!")

    except Exception as e:
        print(f"Error inspecting database: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    inspect_products()