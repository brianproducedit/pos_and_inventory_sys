from fastapi.testclient import TestClient
from src.main import app
from src.models import AnalyticsEvent, User, UserRole, Store
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


def test_switch_store_creates_analytics_event():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Create a store to switch to
    r = client.post('/api/stores', json={'name': 'SwitchStore', 'location': 'X'}, headers=headers)
    assert r.status_code == 201
    store_id = r.json()['id']

    # Switch
    rs = client.post(f'/api/stores/switch/{store_id}', headers=headers)
    assert rs.status_code == 200

    # Verify analytics event
    db = SessionLocal()
    ae = db.query(AnalyticsEvent).filter(AnalyticsEvent.to_store_id == store_id, AnalyticsEvent.event_name == 'store_switch').first()
    assert ae is not None
    assert ae.to_store_id == store_id
    assert ae.user_id is not None
    assert ae.duration_ms is not None
    assert ae.metadata_json is not None
    assert 'success' in ae.metadata_json
    db.close()
