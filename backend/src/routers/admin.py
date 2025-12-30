from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from src.database import get_db
from src.auth import get_current_active_user
from src.services.sync_replay import replay_changes

router = APIRouter()

class ReplayRequest(BaseModel):
    from_seq: int
    to_seq: int
    dry_run: bool = True
    entity_type: str | None = None


@router.post('/replay-changes')
def replay_changes_endpoint(payload: ReplayRequest, db: Session = Depends(get_db), current_user = Depends(get_current_active_user)):
    # Only superadmin allowed for this tooling
    if not current_user or current_user.role.value != 'superadmin':
        raise HTTPException(status_code=403, detail='Forbidden')

    report = replay_changes(db, payload.from_seq, payload.to_seq, dry_run=payload.dry_run, entity_type=payload.entity_type)
    return report
