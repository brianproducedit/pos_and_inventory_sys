from fastapi.testclient import TestClient
from src.main import app
from src.models import AnalyticsEvent, User, UserRole
from src.database import SessionLocal
from src.auth import get_password_hash
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


def test_analytics_summary_counts_and_avg():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create events
    # Create two stores to reference
    r1 = client.post('/api/stores', json={'name': 'analytics-s1', 'location': 'here'}, headers=headers)
    r2 = client.post('/api/stores', json={'name': 'analytics-s2', 'location': 'there'}, headers=headers)
    assert r1.status_code == 201 and r2.status_code == 201
    s1 = r1.json()['id']
    s2 = r2.json()['id']

    client.post('/api/analytics/events', json={'event_name': 'store_quick_switch', 'to_store_id': s1, 'duration_ms': 100}, headers=headers)
    client.post('/api/analytics/events', json={'event_name': 'store_quick_switch', 'to_store_id': s1, 'duration_ms': 200}, headers=headers)
    client.post('/api/analytics/events', json={'event_name': 'store_quick_switch', 'to_store_id': s2, 'duration_ms': 300}, headers=headers)

    r = client.get('/api/analytics/summary', params={'event_name': 'store_quick_switch'}, headers=headers)
    assert r.status_code == 200
    data = r.json()
    assert data['total_count'] >= 3
    assert any(b['store_id'] == s1 and b['count'] >= 2 for b in data['by_store'])
    assert data['avg_duration_ms'] is not None


def test_analytics_summary_forbidden_for_admin():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}
    import uuid
    uname = f"slist_{uuid.uuid4().hex[:6]}"
    resp = client.post('/api/users', json={'username': uname, 'password': 'pass', 'role': 'admin'}, headers=headers)
    assert resp.status_code == 201

    resp = client.post('/auth/token', data={'username': uname, 'password': 'pass'})
    assert resp.status_code == 200
    admin_token = resp.json()['access_token']

    r = client.get('/api/analytics/summary', params={'event_name': 'store_quick_switch'}, headers={'Authorization': f'Bearer {admin_token}'})
    assert r.status_code == 403
