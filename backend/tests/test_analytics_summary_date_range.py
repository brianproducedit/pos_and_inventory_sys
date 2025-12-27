from fastapi.testclient import TestClient
from src.main import app
from src.models import AnalyticsEvent, User, UserRole
from src.database import SessionLocal
from src.auth import get_password_hash
import os
from datetime import datetime, timedelta

client = TestClient(app)


def ensure_superadmin():
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.username == 'superbrian').first()
        if not user:
            test_pw = os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')
            user = User(username='superbrian', password_hash=get_password_hash(test_pw), role=UserRole.superadmin)
            db.add(user)
            db.commit()
    finally:
        db.close()


def get_token(username='superbrian', password=None):
    pw = password or os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')
    ensure_superadmin()
    resp = client.post('/auth/token', data={'username': username, 'password': pw})
    assert resp.status_code == 200
    return resp.json()['access_token']


def test_summary_with_custom_date_range():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    today = datetime.utcnow().date()
    d1 = (today - timedelta(days=5)).isoformat()
    d2 = (today - timedelta(days=3)).isoformat()

    # Create events on different days
    for i in range(5):
        # Ensure a store exists
        rs = client.post('/api/stores', json={'name': 'analytics-range', 'location': 'here'}, headers=headers)
        assert rs.status_code == 201
        sid = rs.json()['id']
        client.post('/api/analytics/events', json={'event_name': 'store_quick_switch', 'to_store_id': sid, 'duration_ms': 10}, headers=headers)

    # Query only the 3-day range (d1...d2)
    r = client.get('/api/analytics/summary', params={'event_name': 'store_quick_switch', 'start_date': d1, 'end_date': d2, 'granularity': 'daily'}, headers=headers)
    assert r.status_code == 200
    data = r.json()
    assert 'labels' in data
    # labels length equals days inclusive
    expected_days = (datetime.fromisoformat(d2).date() - datetime.fromisoformat(d1).date()).days + 1
    assert len(data['labels']) == expected_days
