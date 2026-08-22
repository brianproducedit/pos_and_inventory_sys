import sys
import os
import uuid
from datetime import datetime, timedelta

# Add backend directory to Python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from src.database import SessionLocal, get_engine
from src.models import Base, User, Store, Product, Sale, SaleItem, UserRole
from src.auth import get_password_hash

def seed_demo():
    print("Creating tables if they don't exist...")
    engine = get_engine()
    Base.metadata.create_all(bind=engine)
    
    db = SessionLocal()
    
    # 1. Stores
    print("Seeding stores...")
    harare = db.query(Store).filter_by(name="Harare CBD").first()
    if not harare:
        harare = Store(name="Harare CBD", location="First Street, Harare")
        db.add(harare)
    
    avondale = db.query(Store).filter_by(name="Avondale").first()
    if not avondale:
        avondale = Store(name="Avondale", location="Avondale Shopping Centre")
        db.add(avondale)
        
    db.commit()
    db.refresh(harare)
    
    # 2. Users
    print("Seeding users...")
    users_data = [
        {"username": "demo", "full_name": "Demo Cashier", "role": UserRole.cashier, "store_id": harare.id},
        {"username": "admin", "full_name": "Demo Admin", "role": UserRole.admin, "store_id": harare.id},
        {"username": "superadmin", "full_name": "Demo Superadmin", "role": UserRole.superadmin, "store_id": None},
    ]
    
    for u_data in users_data:
        user = db.query(User).filter_by(username=u_data["username"]).first()
        if not user:
            user = User(
                username=u_data["username"],
                full_name=u_data["full_name"],
                role=u_data["role"],
                password_hash=get_password_hash("demo123"),
                store_id=u_data["store_id"],
                must_change_password=False
            )
            db.add(user)
    db.commit()

    admin_user = db.query(User).filter_by(username="admin").first()

    # 3. Products
    print("Seeding products...")
    products_data = [
        {"name": "Coca-Cola 500ml", "sku": "COCA-500", "price": 1.50, "stock": 120},
        {"name": "Lays Salted 30g", "sku": "LAYS-30G", "price": 0.80, "stock": 85},
        {"name": "Econet Airtime $1", "sku": "ECO-1USD", "price": 1.00, "stock": 500},
        {"name": "Mazoe Orange Crush 2L", "sku": "MAZ-OR-2L", "price": 4.50, "stock": 45},
        {"name": "Bakers Inscore Bread", "sku": "BREAD-INS", "price": 1.00, "stock": 30},
    ]

    product_objects = []
    for p_data in products_data:
        prod = db.query(Product).filter_by(sku=p_data["sku"]).first()
        if not prod:
            prod = Product(
                name=p_data["name"],
                sku=p_data["sku"],
                price=p_data["price"],
                stock_quantity=p_data["stock"],
                store_id=harare.id
            )
            db.add(prod)
        product_objects.append(prod)
    
    db.commit()
    for p in product_objects:
        db.refresh(p)

    # 4. Sales
    print("Seeding sales...")
    now = datetime.utcnow()
    # Check if sales exist
    existing_sales = db.query(Sale).filter_by(store_id=harare.id).count()
    if existing_sales == 0:
        for i in range(15):
            sale_date = now - timedelta(days=(i % 5), hours=i)
            
            sale = Sale(
                transaction_number=f"TXN-DEMO-{1000+i}",
                user_id=admin_user.id,
                store_id=harare.id,
                total_amount=0, # updated later
                payment_method="card" if i % 3 == 0 else "cash",
                created_at=sale_date
            )
            db.add(sale)
            db.flush() # flush to get sale id
            
            total_amount = 0
            num_items = (i % 3) + 1
            for j in range(num_items):
                prod = product_objects[(i + j) % len(product_objects)]
                qty = (j % 2) + 1
                item_total = prod.price * qty
                total_amount += item_total
                
                item = SaleItem(
                    sale_id=sale.id,
                    product_id=prod.id,
                    quantity=qty,
                    unit_price=prod.price,
                    total_price=item_total
                )
                db.add(item)
                
            sale.total_amount = total_amount
            
        db.commit()
    
    print("Demo data seeded successfully in backend database.")
    db.close()

if __name__ == "__main__":
    seed_demo()
