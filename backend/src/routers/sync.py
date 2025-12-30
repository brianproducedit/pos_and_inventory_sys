from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Optional, List, Dict, Any
from datetime import datetime
from sqlalchemy.orm import Session
from src.database import get_db
from src.auth import get_current_active_user
from src.models import Product, AuditLog, Store, User, UserRole, Change
from src.auth import get_password_hash
from pydantic import BaseModel
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError

router = APIRouter()

# Helper to create Change rows safely across DB schemas where optional columns
# (like client_temp_id) might not exist yet (older deployments or test DBs).
# Filters provided kwargs to only columns present in the Change table.
def _make_change(db, **fields):
    # Use inspector to detect actual table columns on the current DB connection
    from sqlalchemy import inspect, func
    inspector = inspect(db.bind)
    try:
        existing_cols = set(c['name'] for c in inspector.get_columns('changes'))
    except Exception:
        # Fallback to model columns if inspection fails
        existing_cols = set(c.name for c in Change.__table__.columns)

    # If the DB doesn't auto-populate server_seq (e.g., create_all without trigger),
    # compute and set it so inserts succeed.
    if 'server_seq' in existing_cols and 'server_seq' not in fields:
        try:
            next_seq = db.query(func.coalesce(func.max(Change.server_seq), 0) + 1).scalar()
            fields['server_seq'] = next_seq
        except Exception:
            # If computing next_seq fails, proceed without setting it and let DB handle or raise
            pass

    filtered = {k: v for k, v in fields.items() if k in existing_cols}

    ch = Change(**filtered)
    db.add(ch)
    db.commit()
    db.refresh(ch)
    return ch


# Simple sync schemas
class SyncChange(BaseModel):
    resource_type: str
    operation: str  # 'create', 'update', 'delete'
    temp_id: Optional[str] = None  # client-side temporary id for newly created records
    id: Optional[int] = None
    data: Optional[Dict[str, Any]] = None
    last_updated: Optional[datetime] = None

class SyncPushRequest(BaseModel):
    client_id: Optional[str] = None
    changes: List[SyncChange]

class SyncConflict(BaseModel):
    resource_type: str
    id: Optional[int]
    message: str
    server_data: Optional[Dict[str, Any]] = None
    suggestion: Optional[str] = None

class SyncPushResponse(BaseModel):
    applied: List[Dict[str, Any]] = []
    conflicts: List[SyncConflict] = []
    id_map: Dict[str, int] = {}


@router.get("/api/sync/changes")
def get_changes(since: Optional[datetime] = Query(None), since_seq: Optional[int] = Query(None), limit: int = Query(500), types: Optional[str] = Query(None), db: Session = Depends(get_db), current_user = Depends(get_current_active_user)):
    """Return changed records since `since` timestamp or `since_seq` server sequence.
    Backwards compatible: if `since_seq` is provided, use the `changes` table; else fall back to timestamp-based changes for existing clients."""
    if since_seq is not None:
        # Use changes table for efficient ordered pulls
        q = db.query(Change).filter(Change.server_seq > since_seq)
        if types:
            requested_types = set(types.split(','))
            q = q.filter(Change.entity_type.in_(requested_types))
        q = q.order_by(Change.server_seq.asc()).limit(limit)
        rows = q.all()

        changes = []
        for r in rows:
            changes.append({
                'server_seq': r.server_seq,
                'entity_type': r.entity_type,
                'entity_id': r.entity_id,
                'operation': r.operation,
                'payload': r.payload,
                'origin_client_id': r.origin_client_id,
                'client_temp_id': r.client_temp_id,
                'created_at': r.created_at.isoformat() if r.created_at else None,
            })

        # head_seq: current highest seq
        head = db.query(Change.server_seq).order_by(Change.server_seq.desc()).first()
        head_seq = head[0] if head else since_seq
        return {'changes': changes, 'head_seq': head_seq}

    # Backwards compatible timestamp-based response
    if not since:
        raise HTTPException(status_code=400, detail="Missing 'since' timestamp or 'since_seq' parameter")

    requested_types = set(types.split(',')) if types else set()
    changes = {}

    # Products
    if not requested_types or 'products' in requested_types:
        prods = db.query(Product).filter(or_(Product.updated_at > since, Product.created_at > since)).all()
        prod_list = []
        for p in prods:
            prod_list.append({
                'id': p.id,
                'resource_type': 'product',
                'operation': 'upsert',
                'data': {
                    'name': p.name,
                    'description': p.description,
                    'price': p.price,
                    'stock_quantity': p.stock_quantity,
                    'is_active': p.is_active,
                    'store_id': p.store_id,
                },
                'updated_at': p.updated_at.isoformat() if p.updated_at else None,
            })
        changes['products'] = prod_list

    # Deletions (based on audit logs)
    del_entries = db.query(AuditLog).filter(AuditLog.action.like('DELETE_%'), AuditLog.created_at > since).all()
    deletes = []
    for d in del_entries:
        deletes.append({'resource_type': d.resource_type, 'id': d.resource_id, 'action': d.action, 'timestamp': d.created_at.isoformat()})
    changes['deletes'] = deletes

    return {'changes': changes, 'server_time': datetime.utcnow().isoformat()}

@router.post("/api/sync/push")
def push_changes(payload: SyncPushRequest, db: Session = Depends(get_db), current_user = Depends(get_current_active_user)) -> SyncPushResponse:
    """Apply client changes (create/update/delete). Returns applied changes, conflicts, and mapping of temp ids to server ids."""
    applied = []
    conflicts = []
    id_map = {}

    for ch in payload.changes:
        # PRODUCTS
        if ch.resource_type == 'product':
            # Create
            if ch.operation == 'create':
                data = ch.data or {}
                # Validate required fields to avoid DB integrity errors
                if data.get('store_id') is None:
                    raise HTTPException(status_code=400, detail=f"Product create missing required field 'store_id' for temp_id {ch.temp_id or '<unknown>'}")

                # Idempotency: if client supplied a temp_id and we've already applied it, return existing mapping
                if ch.temp_id:
                    try:
                        existing = db.query(Change).filter(Change.client_temp_id == ch.temp_id, Change.origin_client_id == payload.client_id, Change.entity_type == 'product', Change.operation == 'create').first()
                        if existing and existing.entity_id:
                            # Map temp to existing server id and skip creating a duplicate
                            id_map[ch.temp_id] = int(existing.entity_id)
                            applied.append({'resource_type': 'product', 'operation': 'create', 'id': int(existing.entity_id), 'server_seq': existing.server_seq})
                            continue
                    except Exception:
                        # If DB schema doesn't have client_temp_id (pre-migration), ignore dedicated idempotency and proceed
                        existing = None

                p = Product(
                    name=data.get('name') or 'Unnamed',
                    description=data.get('description'),
                    price=data.get('price') or 0.0,
                    stock_quantity=data.get('stock_quantity') or 0,
                    is_active=data.get('is_active', True),
                    store_id=data.get('store_id')
                )
                db.add(p)
                db.commit()
                db.refresh(p)
                # Record change (best-effort; if change recording fails due to older schema, continue)
                try:
                    ch_entry = _make_change(db, entity_type='product', entity_id=str(p.id), operation='create', payload={'data': data}, client_temp_id=ch.temp_id, origin_client_id=payload.client_id)
                    applied.append({'resource_type': 'product', 'operation': 'create', 'id': p.id, 'server_seq': ch_entry.server_seq})
                except Exception:
                    db.rollback()
                    applied.append({'resource_type': 'product', 'operation': 'create', 'id': p.id})

                if ch.temp_id:
                    id_map[ch.temp_id] = p.id

            elif ch.operation == 'update':
                if not ch.id:
                    conflicts.append(SyncConflict(resource_type='product', id=None, message='Update missing server id').dict())
                    continue
                p = db.query(Product).filter(Product.id == ch.id).first()
                if not p:
                    conflicts.append(SyncConflict(resource_type='product', id=ch.id, message='Server record not found').dict())
                    continue

                # Compare timestamps if provided
                if ch.last_updated and p.updated_at and ch.last_updated < p.updated_at:
                    # Allow superadmin to force an overwrite by including `_force: true` in `data`
                    if ch.data and ch.data.get('_force') and current_user.role.value == 'superadmin':
                        # apply the update despite timestamp mismatch
                        ch.data.pop('_force', None)
                    else:
                        # Conflict — server has newer data
                        conflicts.append(SyncConflict(resource_type='product', id=p.id, message='Conflict: server has newer record', server_data={
                            'id': p.id,
                            'name': p.name,
                            'description': p.description,
                            'price': p.price,
                            'stock_quantity': p.stock_quantity,
                            'is_active': p.is_active,
                            'store_id': p.store_id,
                            'updated_at': p.updated_at.isoformat() if p.updated_at else None
                        }, suggestion='fetch_or_force').dict())
                        continue

                data = ch.data or {}
                for k, v in data.items():
                    if hasattr(p, k):
                        setattr(p, k, v)
                db.commit()
                db.refresh(p)
                # Record change (best-effort)
                try:
                    ch_entry = _make_change(db, entity_type='product', entity_id=str(p.id), operation='update', payload={'data': data}, origin_client_id=payload.client_id)
                    applied.append({'resource_type': 'product', 'operation': 'update', 'id': p.id, 'server_seq': ch_entry.server_seq})
                except Exception:
                    db.rollback()
                    applied.append({'resource_type': 'product', 'operation': 'update', 'id': p.id})

            elif ch.operation == 'delete':
                if not ch.id:
                    conflicts.append(SyncConflict(resource_type='product', id=None, message='Delete missing server id').dict())
                    continue
                p = db.query(Product).filter(Product.id == ch.id).first()
                if not p:
                    # Already deleted or doesn't exist
                    conflicts.append(SyncConflict(resource_type='product', id=ch.id, message='Server record not found').dict())
                    continue
                # Soft delete using is_active flag
                p.is_active = False
                db.commit()
                db.refresh(p)
                # Log audit
                al = AuditLog(user_id=current_user.id, action='DELETE_PRODUCT', resource_type='product', resource_id=p.id, details=f"Deleted via sync by client {payload.client_id}")
                db.add(al)
                db.commit()
                # Record change (best-effort)
                try:
                    ch_entry = _make_change(db, entity_type='product', entity_id=str(p.id), operation='delete', payload={}, origin_client_id=payload.client_id)
                    applied.append({'resource_type': 'product', 'operation': 'delete', 'id': p.id, 'server_seq': ch_entry.server_seq})
                except Exception:
                    db.rollback()
                    applied.append({'resource_type': 'product', 'operation': 'delete', 'id': p.id})

            else:
                conflicts.append(SyncConflict(resource_type='product', id=ch.id, message='Operation not supported for product').dict())
                continue

        # STORES
        elif ch.resource_type == 'store':
            if ch.operation == 'create':
                data = ch.data or {}
                s = Store(name=data.get('name') or 'Unnamed Store', location=data.get('location'), is_active=data.get('is_active', True))
                db.add(s)
                db.commit()
                db.refresh(s)
                applied.append({'resource_type': 'store', 'operation': 'create', 'id': s.id})
                # Record change
                try:
                    ch_entry = _make_change(db, entity_type='store', entity_id=str(s.id), operation='create', payload={'data': data}, client_temp_id=ch.temp_id, origin_client_id=payload.client_id)
                except Exception:
                    db.rollback()
                if ch.temp_id:
                    id_map[ch.temp_id] = s.id

            elif ch.operation == 'update':
                if not ch.id:
                    conflicts.append(SyncConflict(resource_type='store', id=None, message='Update missing server id').dict())
                    continue
                s = db.query(Store).filter(Store.id == ch.id).first()
                if not s:
                    conflicts.append(SyncConflict(resource_type='store', id=ch.id, message='Server record not found').dict())
                    continue
                if ch.last_updated and s.updated_at and ch.last_updated < s.updated_at:
                    if ch.data and ch.data.get('_force') and current_user.role.value == 'superadmin':
                        ch.data.pop('_force', None)
                    else:
                        conflicts.append(SyncConflict(resource_type='store', id=s.id, message='Conflict: server has newer record', server_data={'id': s.id, 'name': s.name, 'location': s.location, 'is_active': s.is_active, 'updated_at': s.updated_at.isoformat() if s.updated_at else None}, suggestion='fetch_or_force').dict())
                        continue
                data = ch.data or {}
                for k, v in data.items():
                    if hasattr(s, k):
                        setattr(s, k, v)
                db.commit()
                db.refresh(s)
                try:
                    ch_entry = _make_change(db, entity_type='store', entity_id=str(s.id), operation='update', payload={'data': data}, origin_client_id=payload.client_id)
                    applied.append({'resource_type': 'store', 'operation': 'update', 'id': s.id, 'server_seq': ch_entry.server_seq})
                except Exception:
                    db.rollback()
                    applied.append({'resource_type': 'store', 'operation': 'update', 'id': s.id})

            elif ch.operation == 'delete':
                if not ch.id:
                    conflicts.append(SyncConflict(resource_type='store', id=None, message='Delete missing server id').dict())
                    continue
                s = db.query(Store).filter(Store.id == ch.id).first()
                if not s:
                    conflicts.append(SyncConflict(resource_type='store', id=ch.id, message='Server record not found').dict())
                    continue
                s.is_active = False
                db.commit()
                db.refresh(s)
                al = AuditLog(user_id=current_user.id, action='DELETE_STORE', resource_type='store', resource_id=s.id, details=f"Deleted via sync by client {payload.client_id}")
                db.add(al)
                db.commit()
                try:
                    ch_entry = _make_change(db, entity_type='store', entity_id=str(s.id), operation='delete', payload={}, origin_client_id=payload.client_id)
                    applied.append({'resource_type': 'store', 'operation': 'delete', 'id': s.id, 'server_seq': ch_entry.server_seq})
                except Exception:
                    db.rollback()
                    applied.append({'resource_type': 'store', 'operation': 'delete', 'id': s.id})

            else:
                conflicts.append(SyncConflict(resource_type='store', id=ch.id, message='Operation not supported for store').dict())
                continue

        # USERS
        elif ch.resource_type == 'user':
            if ch.operation == 'create':
                data = ch.data or {}
                uname = data.get('username')
                if not uname:
                    conflicts.append(SyncConflict(resource_type='user', id=None, message='Create missing username').dict())
                    continue
                pw = data.get('password')
                if not pw:
                    import secrets
                    pw = secrets.token_urlsafe(12)
                    must_change = True
                else:
                    must_change = data.get('must_change_password', True)
                role_val = data.get('role', 'cashier')
                try:
                    u = User(username=uname, password_hash=get_password_hash(pw), role=UserRole(role_val), is_active=data.get('is_active', True), store_id=data.get('store_id'), must_change_password=must_change)
                    db.add(u)
                    db.commit()
                    db.refresh(u)
                    applied.append({'resource_type': 'user', 'operation': 'create', 'id': u.id})
                    # Record change
                    try:
                        ch_entry = _make_change(db, entity_type='user', entity_id=str(u.id), operation='create', payload={'data': data}, client_temp_id=ch.temp_id, origin_client_id=payload.client_id)
                    except Exception:
                        db.rollback()
                    if ch.temp_id:
                        id_map[ch.temp_id] = u.id
                except IntegrityError:
                    db.rollback()
                    conflicts.append(SyncConflict(resource_type='user', id=None, message='Username already exists').dict())

            elif ch.operation == 'update':
                if not ch.id:
                    conflicts.append(SyncConflict(resource_type='user', id=None, message='Update missing server id').dict())
                    continue
                u = db.query(User).filter(User.id == ch.id).first()
                if not u:
                    conflicts.append(SyncConflict(resource_type='user', id=ch.id, message='Server record not found').dict())
                    continue
                if ch.last_updated and u.updated_at and ch.last_updated < u.updated_at:
                    if ch.data and ch.data.get('_force') and current_user.role.value == 'superadmin':
                        ch.data.pop('_force', None)
                    else:
                        conflicts.append(SyncConflict(resource_type='user', id=u.id, message='Conflict: server has newer record', server_data={'id': u.id, 'username': u.username, 'role': u.role.name if u.role else None, 'is_active': u.is_active, 'store_id': u.store_id, 'updated_at': u.updated_at.isoformat() if u.updated_at else None}, suggestion='fetch_or_force').dict())
                        continue
                data = ch.data or {}
                pw = data.get('password')
                if pw:
                    u.password_hash = get_password_hash(pw)
                    u.must_change_password = data.get('must_change_password', True)
                if 'role' in data:
                    # Only allow role escalation if current_user is superadmin
                    if current_user.role.value != 'superadmin' and data.get('role') in ['superadmin', 'admin']:
                        conflicts.append(SyncConflict(resource_type='user', id=u.id, message='Permission denied to change role').dict())
                        continue
                    u.role = UserRole(data.get('role'))
                for k, v in data.items():
                    if k == 'password' or k == 'role':
                        continue
                    if hasattr(u, k):
                        setattr(u, k, v)
                db.commit()
                db.refresh(u)
                applied.append({'resource_type': 'user', 'operation': 'update', 'id': u.id})

            elif ch.operation == 'delete':
                if not ch.id:
                    conflicts.append(SyncConflict(resource_type='user', id=None, message='Delete missing server id').dict())
                    continue
                u = db.query(User).filter(User.id == ch.id).first()
                if not u:
                    conflicts.append(SyncConflict(resource_type='user', id=ch.id, message='Server record not found').dict())
                    continue
                u.is_active = False
                db.commit()
                db.refresh(u)
                al = AuditLog(user_id=current_user.id, action='DELETE_USER', resource_type='user', resource_id=u.id, details=f"Deleted via sync by client {payload.client_id}")
                db.add(al)
                db.commit()
                applied.append({'resource_type': 'user', 'operation': 'delete', 'id': u.id})

            else:
                conflicts.append(SyncConflict(resource_type='user', id=ch.id, message='Operation not supported for user').dict())
                continue

        else:
            conflicts.append(SyncConflict(resource_type=ch.resource_type, id=ch.id, message='Resource type not supported yet').dict())
            continue
        

    return SyncPushResponse(applied=applied, conflicts=conflicts, id_map=id_map)
