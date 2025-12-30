import sys, os
# Ensure backend package root is on sys.path
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from fastapi.testclient import TestClient
from src.main import app
from src.database import SessionLocal
from src.models import AnalyticsEvent, User
from src.auth import get_password_hash
import os
from datetime import datetime, timedelta

client = TestClient(app)

# Ensure superadmin
from src.models import UserRole
s = SessionLocal()
user = s.query(User).filter(User.username=='superbrian').first()
if not user:
    user = User(username='superbrian', password_hash=get_password_hash('changeme_test_password'), role=UserRole.superadmin)
    s.add(user)
    s.commit()
    s.refresh(user)

# Create store
headers = {'Authorization': f"Bearer {client.post('/auth/token', data={'username':'superbrian','password':'changeme_test_password'}).json()['access_token']}"}
rs = client.post('/api/stores', json={'name':'analytics-series-store', 'location':'here'}, headers=headers)
print('store create status', rs.status_code, rs.text)
tid = rs.json().get('id')
print('tid', tid)

# Insert events
today = datetime.utcnow().date()
dates = [today - timedelta(days=2), today - timedelta(days=1), today]
for i, d in enumerate(dates):
    for j in range(i+1):
        evt = AnalyticsEvent(event_name='store_quick_switch', from_store_id=None, to_store_id=tid, duration_ms=10, metadata={'note':'test switch'}, user_id=user.id, created_at=datetime(d.year, d.month, d.day, 12, 0, 0))
        s.add(evt)
s.commit()

r = client.get('/api/analytics/summary', params={'event_name':'store_quick_switch','since_days':3,'granularity':'daily'}, headers=headers)
print('summary code', r.status_code)
print(r.json())
s.close()
