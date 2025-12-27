from fastapi.testclient import TestClient
from src.main import app
from src.models import AnalyticsEvent, User, UserRole
from src.database import SessionLocal
from src.auth import get_password_hash
import os
import json

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


def test_list_analytics_events_superadmin():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create three stores and post events against them
    sids = []
    for i in range(3):
        rs = client.post('/api/stores', json={'name': f'analytics-s{i}', 'location': 'loc'}, headers=headers)
        assert rs.status_code == 201
        sids.append(rs.json()['id'])

    for i in range(3):
        payload = {'event_name': 'store_quick_switch', 'to_store_id': sids[i], 'duration_ms': i * 10}
        r = client.post('/api/analytics/events', json=payload, headers=headers)
        assert r.status_code == 201

    r = client.get('/api/analytics/events', headers=headers)
    assert r.status_code == 200
    data = r.json()
    assert 'events' in data
    assert data['total_count'] >= 3
    assert any(e['event_name'] == 'store_quick_switch' for e in data['events'])


def test_list_analytics_events_forbidden_for_admin():
    # Create admin user
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}
    import uuid
    uname = f"alist_{uuid.uuid4().hex[:6]}"
    resp = client.post('/api/users', json={'username': uname, 'password': 'pass', 'role': 'admin'}, headers=headers)
    assert resp.status_code == 201
    admin_id = resp.json()['id']

    # Login as admin
    resp = client.post('/auth/token', data={'username': uname, 'password': 'pass'})
    assert resp.status_code == 200
    admin_token = resp.json()['access_token']

    r = client.get('/api/analytics/events', headers={'Authorization': f'Bearer {admin_token}'})
    assert r.status_code == 403
