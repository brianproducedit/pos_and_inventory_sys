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


def test_switch_to_all_stores():
    token = get_token()
    headers = {'Authorization': f'Bearer {token}'}

    # Switch to global/all stores using 0
    rs = client.post('/api/stores/switch/0', headers=headers)
    assert rs.status_code == 200
    data = rs.json()
    # Backend should indicate current_store is null
    assert data['current_store']['id'] is None

    # Verify analytics event created (to_store_id is null)
    db = SessionLocal()
    ae = db.query(AnalyticsEvent).filter(AnalyticsEvent.event_name == 'store_switch').order_by(AnalyticsEvent.id.desc()).first()
    assert ae is not None
    assert ae.to_store_id is None
    db.close()
