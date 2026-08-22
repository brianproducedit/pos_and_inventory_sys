import sys
import os
from datetime import datetime

# Ensure src package is importable when running tests directly
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from src.schemas import AuditLogResponse

def test_audit_log_response_accepts_service_dict():
    sample = {
        "id": 1,
        "user_id": 2,
        "store_id": 3,
        "action": "CREATE_SALE",
        "entity_type": "sale",
        "entity_id": 10,
        "details": {"total_amount": 100.0, "items": 2},
        "ip_address": "127.0.0.1",
        "user_agent": "pytest",
        "timestamp": datetime.utcnow(),
    }

    resp = AuditLogResponse.model_validate(sample)
    assert resp.id == 1
    assert resp.entity_type == "sale"
    assert isinstance(resp.timestamp, datetime)
    assert isinstance(resp.details, dict)
