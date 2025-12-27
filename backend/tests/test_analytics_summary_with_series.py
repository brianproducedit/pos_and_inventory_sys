from fastapi.testclient import TestClient
from src.main import app
from src.models import AnalyticsEvent, User, UserRole
from src.database import SessionLocal
from src.auth import get_password_hash
from datetime import datetime, timedelta
import os

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


def test_summary_with_daily_series():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create events across the last 3 days
    today = datetime.utcnow().date()
    dates = [today - timedelta(days=2), today - timedelta(days=1), today]

    # Ensure stores exist; create one and use its id
    rs = client.post('/api/stores', json={'name': 'analytics-series-store', 'location': 'here'}, headers=headers)
    assert rs.status_code == 201
    tid = rs.json()['id']

    # Insert events directly into DB with created_at set to different days so series shows daily buckets
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.username == 'superbrian').first()
        for i, d in enumerate(dates):
            for j in range(i + 1):  # 1 event on day0, 2 on day1, 3 on day2
                evt = AnalyticsEvent(
                    event_name='store_quick_switch',
                    from_store_id=None,
                    to_store_id=tid,
                    duration_ms=10,
                    metadata={'note': 'test switch'},
                    user_id=user.id,
                    created_at=datetime(d.year, d.month, d.day, 12, 0, 0)
                )
                db.add(evt)
        db.commit()
    finally:
        db.close()

    r = client.get('/api/analytics/summary', params={'event_name': 'store_quick_switch', 'since_days': 3, 'granularity': 'daily'}, headers=headers)
    assert r.status_code == 200
    data = r.json()
    assert data.get('labels') is not None
    assert len(data['labels']) == 3
    # find store 1 series
    found = None
    for b in data['by_store']:
        if b['store_id'] == 1:
            found = b
            break
    assert found is not None
    assert 'series' in found
    assert len(found['series']) == 3
