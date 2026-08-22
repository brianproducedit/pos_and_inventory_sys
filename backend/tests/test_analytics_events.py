from fastapi.testclient import TestClient
from src.main import app
from src.models import AnalyticsEvent, User, UserRole
from src.database import SessionLocal
from src.auth import get_password_hash
import json
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


def test_create_store_quick_switch_event():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Ensure a store exists to reference
    rs = client.post('/api/stores', json={'name': 'analytics-store', 'location': 'here'}, headers=headers)
    assert rs.status_code == 201
    store_id = rs.json()['id']

    payload = {
        'event_name': 'store_quick_switch',
        'from_store_id': None,
        'to_store_id': store_id,
        'duration_ms': 123,
        'metadata': {'note': 'test switch'},
    }

    r = client.post('/api/analytics/events', json=payload, headers=headers)
    assert r.status_code == 201
    data = r.json()
    assert data['event_name'] == 'store_quick_switch'
    assert data['to_store_id'] == store_id
    assert isinstance(data['id'], int)

    # Verify stored in DB
    db = SessionLocal()
    ae = db.query(AnalyticsEvent).filter(AnalyticsEvent.id == data['id']).first()
    assert ae is not None
    assert ae.event_name == 'store_quick_switch'
    assert ae.duration_ms == 123
    db.close()
