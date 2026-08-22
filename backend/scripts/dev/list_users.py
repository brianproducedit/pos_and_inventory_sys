import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from src.database import SessionLocal
from src.models import User

db = SessionLocal()
users = db.query(User).all()
for u in users:
    print(u.id, u.username, getattr(u.role, 'value', str(u.role)), u.store_id)
