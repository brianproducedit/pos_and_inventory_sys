from fastapi.testclient import TestClient
from src.main import app
import os

client = TestClient(app)

# Ensure superadmin
from src.database import SessionLocal
from src.models import User, UserRole
from src.auth import get_password_hash

db = SessionLocal()
user = db.query(User).filter(User.username=='superbrian').first()
if not user:
    test_pw = os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')
    user = User(username='superbrian', password_hash=get_password_hash(test_pw), role=UserRole.superadmin)
    db.add(user)
    db.commit()
else:
    test_pw = os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')
    user.password_hash = get_password_hash(test_pw)
    user.role = UserRole.superadmin
    db.commit()

# login
resp = client.post('/auth/token', data={'username':'superbrian','password': os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')})
print('login', resp.status_code, resp.text)
access = resp.json().get('access_token')
headers = {'Authorization': f'Bearer {access}'}

# create store
rs = client.post('/api/stores', json={'name':'debug-store','location':'here'}, headers=headers)
print('create store', rs.status_code, rs.text)
store_id = rs.json().get('id')

# create product
rp = client.post('/api/products', json={'name': 'papi', 'price': 9.99, 'stock_quantity': 5, 'is_active': True}, headers=headers)
print('create product', rp.status_code, rp.text)

# cleanup
rd = client.delete(f'/api/stores/{store_id}/hard', headers=headers)
print('delete store', rd.status_code, rd.text)
