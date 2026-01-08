from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Optional, List, Dict, Any
from datetime import datetime
from sqlalchemy.orm import Session
from sqlalchemy import or_, func
from src.database import get_db
from src.auth import get_current_active_user
from src.models import Product, AuditLog, Store, User, UserRole, Change, Sale, SaleItem, InventoryLog, AnalyticsEvent, UserSettings, StoreSettings, SystemSettings
from src.auth import get_password_hash
from pydantic import BaseModel
from sqlalchemy.exc import IntegrityError
from src.feature_flags import is_feature_enabled
from src.metrics import (
    record_sync_operation, record_sync_conflict, update_sync_queue_size,
    time_sync_operation, record_error
)

router = APIRouter()

# Helper to create Change rows safely across DB schemas where optional columns
# (like client_temp_id) might not exist yet (older deployments or test DBs).
# Filters provided kwargs to only columns present in the Change table.
def _make_change(db, **fields):
    # Use model columns as the source of truth
    existing_cols = set(c.name for c in Change.__table__.columns)

    # If the DB doesn't auto-populate server_seq (e.g., create_all without trigger),
    # compute and set it so inserts succeed.
    if 'server_seq' in existing_cols and 'server_seq' not in fields:
        try:
            # For empty table, max returns None, so coalesce to 0, then add 1 = 1
            max_seq = db.query(func.max(Change.server_seq)).scalar()
            next_seq = (max_seq or 0) + 1
            fields['server_seq'] = next_seq
        except Exception as e:
            # If computing next_seq fails, try a simpler approach
            try:
                count = db.query(Change).count()
                fields['server_seq'] = count + 1
            except Exception:
                # Last resort: use a fixed value (not ideal but better than failing)
                fields['server_seq'] = 1

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

    # Check if sync is enabled via feature flags
    if not is_feature_enabled('SYNC_ENABLED'):
        raise HTTPException(status_code=503, detail="Sync service is temporarily disabled")

    with time_sync_operation('pull'):
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
            record_sync_operation('pull', 'success')
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

        record_sync_operation('pull', 'success')
        return {'changes': changes, 'server_time': datetime.utcnow().isoformat()}

@router.get("/api/sync/initial")
def get_initial_data(db: Session = Depends(get_db), current_user = Depends(get_current_active_user)):
    """Return initial snapshot of all data for seeding client database."""

    # Check if sync is enabled via feature flags
    if not is_feature_enabled('SYNC_ENABLED'):
        raise HTTPException(status_code=503, detail="Sync service is temporarily disabled")

    with time_sync_operation('initial_sync'):
        # Get all active users (for authentication and reference)
        users = db.query(User).filter(User.is_active == True).all()
        user_list = []
        for u in users:
            user_list.append({
                'id': u.id,
                'username': u.username,
                'full_name': u.full_name,
                'role': u.role.value if hasattr(u.role, 'value') else str(u.role),
                'store_id': u.store_id,
                'is_active': u.is_active,
                'created_at': u.created_at.isoformat() if u.created_at else None,
                'updated_at': u.updated_at.isoformat() if u.updated_at else None,
            })

        # Get all active products
        products = db.query(Product).filter(Product.is_active == True).all()
        product_list = []
        for p in products:
            product_list.append({
                'id': p.id,
                'store_id': p.store_id,
                'name': p.name,
                'description': p.description,
                'price': p.price,
                'stock_quantity': p.stock_quantity,
                'sku': p.sku if hasattr(p, 'sku') else None,
                'is_active': p.is_active,
                'created_at': p.created_at.isoformat() if p.created_at else None,
                'updated_at': p.updated_at.isoformat() if p.updated_at else None,
            })

        # Get all active stores (for reference)
        stores = db.query(Store).filter(Store.is_active == True).all()
        store_list = []
        for s in stores:
            store_list.append({
                'id': s.id,
                'name': s.name,
                'location': s.location,
                'is_active': s.is_active,
                'created_at': s.created_at.isoformat() if s.created_at else None,
                'updated_at': s.updated_at.isoformat() if s.updated_at else None,
            })

        # Get recent transactions (last 1000 for initial sync to avoid overwhelming clients)
        transactions = db.query(Sale).order_by(Sale.created_at.desc()).limit(1000).all()
        transaction_list = []
        for t in transactions:
            # Get sale items for this transaction
            items = db.query(SaleItem).filter(SaleItem.sale_id == t.id).all()
            item_list = []
            for item in items:
                item_list.append({
                    'product_id': item.product_id,
                    'quantity': item.quantity,
                    'unit_price': item.unit_price,
                    'total_price': item.total_price,
                })

            transaction_list.append({
                'id': t.id,
                'transaction_number': t.transaction_number,
                'store_id': t.store_id,
                'user_id': t.user_id,
                'total_amount': t.total_amount,
                'payment_method': t.payment_method,
                'payment_reference': t.paynow_reference,
                'status': t.status,
                'items': item_list,
                'created_at': t.created_at.isoformat() if t.created_at else None,
                'updated_at': None,  # Sales don't have updated_at field
            })

        record_sync_operation('initial_sync', 'success')
        return {
            'users': user_list,
            'products': product_list,
            'stores': store_list,
            'transactions': transaction_list,
            'server_time': datetime.utcnow().isoformat()
        }

@router.post("/api/sync/push")
def push_changes(payload: SyncPushRequest, db: Session = Depends(get_db), current_user = Depends(get_current_active_user)) -> SyncPushResponse:
    """Apply client changes (create/update/delete). Returns applied changes, conflicts, and mapping of temp ids to server ids."""

    # Check if sync is enabled via feature flags
    if not is_feature_enabled('SYNC_ENABLED'):
        raise HTTPException(status_code=503, detail="Sync service is temporarily disabled")

    print(f"📥 SYNC PUSH: Received {len(payload.changes)} changes from client_id: {payload.client_id}")
    user_changes = [c for c in payload.changes if c.resource_type == 'user']
    if user_changes:
        print(f"👥 SYNC PUSH: {len(user_changes)} user changes:")
        for uc in user_changes:
            print(f"   - {uc.operation} user: {uc.data.get('username') if uc.data else 'N/A'} (temp_id: {uc.temp_id})")

    with time_sync_operation('push'):
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
                            # Continue with update despite conflict (conflict is informational)

                    data = ch.data or {}
                    for k, v in data.items():
                        if k == 'id':  # Never update id (primary key)
                            continue
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
                    # Delete dependent rows first to ensure referential integrity is maintained
                    sale_items_deleted = db.query(SaleItem).filter(SaleItem.product_id == p.id).delete()
                    inventory_logs_deleted = db.query(InventoryLog).filter(InventoryLog.product_id == p.id).delete()
                    # Hard delete the product
                    db.delete(p)
                    db.commit()
                    # Log audit
                    al = AuditLog(user_id=current_user.id, action='DELETE_PRODUCT', resource_type='product', resource_id=ch.id, details=f"Deleted via sync by client {payload.client_id}")
                    db.add(al)
                    db.commit()
                    # Record change (best-effort)
                    try:
                        ch_entry = _make_change(db, entity_type='product', entity_id=str(ch.id), operation='delete', payload={}, origin_client_id=payload.client_id)
                        applied.append({'resource_type': 'product', 'operation': 'delete', 'id': ch.id, 'server_seq': ch_entry.server_seq})
                    except Exception:
                        db.rollback()
                        applied.append({'resource_type': 'product', 'operation': 'delete', 'id': ch.id})

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
                        if k == 'id':  # Never update id (primary key)
                            continue
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

                    # Hard delete the store and all related data
                    from src.store_utils import hard_delete_store
                    result = hard_delete_store(db, ch.id)

                    # Log the hard delete action
                    al = AuditLog(user_id=current_user.id, action='DELETE_STORE', resource_type='store', resource_id=ch.id, details=f"Hard deleted via sync by client {payload.client_id}")
                    db.add(al)
                    db.commit()

                    try:
                        ch_entry = _make_change(db, entity_type='store', entity_id=str(ch.id), operation='delete', payload={}, origin_client_id=payload.client_id)
                        applied.append({'resource_type': 'store', 'operation': 'delete', 'id': ch.id, 'server_seq': ch_entry.server_seq})
                    except Exception:
                        db.rollback()
                        applied.append({'resource_type': 'store', 'operation': 'delete', 'id': ch.id})

                else:
                    conflicts.append(SyncConflict(resource_type='store', id=ch.id, message='Operation not supported for store').dict())
                    continue

            # USERS
            elif ch.resource_type == 'user':
                if ch.operation == 'create':
                    data = ch.data or {}
                    uname = data.get('username')
                    print(f"🔵 SYNC: Received user creation request - username: {uname}, data: {data}")
                    if not uname:
                        conflicts.append(SyncConflict(resource_type='user', id=None, message='Create missing username').dict())
                        continue
                    pw = data.get('password')
                    if not pw:
                        import secrets
                        pw = secrets.token_urlsafe(12)
                        must_change = True
                        print(f"⚠️ SYNC: No password provided for {uname}, generating random password")
                    else:
                        must_change = data.get('must_change_password', True)
                        print(f"✅ SYNC: Password provided for {uname}")
                    role_val = data.get('role', 'cashier')
                    try:
                        u = User(username=uname, password_hash=get_password_hash(pw), role=UserRole(role_val), is_active=data.get('is_active', True), store_id=data.get('store_id'), must_change_password=must_change)
                        db.add(u)
                        db.commit()
                        db.refresh(u)
                        print(f"✅ SYNC: User {uname} created with ID {u.id}")
                        applied.append({'resource_type': 'user', 'operation': 'create', 'id': u.id})
                        # Record change
                        try:
                            ch_entry = _make_change(db, entity_type='user', entity_id=str(u.id), operation='create', payload={'data': data}, client_temp_id=ch.temp_id, origin_client_id=payload.client_id)
                        except Exception:
                            db.rollback()
                        if ch.temp_id:
                            id_map[ch.temp_id] = u.id
                            print(f"✅ SYNC: Mapped temp_id {ch.temp_id} -> server_id {u.id}")
                    except IntegrityError as e:
                        db.rollback()
                        print(f"❌ SYNC: IntegrityError creating user {uname}: {e}")
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
                        if k in ('password', 'role', 'id'):  # Never update id (primary key)
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

            # TRANSACTIONS/SALES (Flutter uses 'transaction', backend uses 'sales' table)
            elif ch.resource_type == 'transaction' or ch.resource_type == 'sale':
                if ch.operation == 'create':
                    data = ch.data or {}
                    # Validate required fields
                    user_id = data.get('user_id') or current_user.id
                    store_id = data.get('store_id')
                    if not store_id:
                        conflicts.append(SyncConflict(resource_type='transaction', id=None, message='Transaction missing store_id').dict())
                        continue
                    
                    # Use provided transaction_number if present; we'll ensure a fallback after flush
                    # Ensure transaction_number is not null at insert: use client-provided or a temp placeholder we can replace after flush
                    txn_num_initial = data.get('transaction_number') or (f"temp-{ch.temp_id}" if ch.temp_id else 'temp-unknown')
                    sale = Sale(
                        user_id=user_id,
                        store_id=store_id,
                        transaction_number=txn_num_initial,
                        total_amount=data.get('total_amount', 0.0),
                        payment_method=data.get('payment_method', 'cash'),
                        paynow_reference=data.get('paynow_reference'),
                        status=data.get('status', 'completed'),
                    )
                    
                    # Pre-validate all items BEFORE adding sale to database
                    items = data.get('items', [])
                    has_invalid_item = False
                    sale_items_to_add = []
                    
                    for item in items:
                        product_id = item.get('product_id')
                        
                        # Resolve temp_id references to server_id
                        if isinstance(product_id, str) and product_id.startswith('t'):
                            # This is a temp_id reference
                            if product_id in id_map:
                                product_id = id_map[product_id]
                            else:
                                # Temp_id not yet resolved - this shouldn't happen if changes are ordered correctly
                                conflicts.append(SyncConflict(
                                    resource_type='transaction', 
                                    id=None, 
                                    message=f'Transaction item references unresolved temp_id: {product_id}'
                                ).dict())
                                has_invalid_item = True
                                break
                        
                        # Verify the product exists in the database
                        if product_id is not None:
                            product = db.query(Product).filter(Product.id == product_id).first()
                            if not product:
                                conflicts.append(SyncConflict(
                                    resource_type='transaction',
                                    id=None,
                                    message=f'Transaction item references non-existent product_id: {product_id}'
                                ).dict())
                                has_invalid_item = True
                                break
                        
                        sale_items_to_add.append({
                            'product_id': product_id,
                            'quantity': item.get('quantity', 1),
                            'unit_price': item.get('unit_price', 0.0),
                            'total_price': item.get('total_price', 0.0)
                        })
                    
                    # Skip this transaction entirely if any item is invalid
                    if has_invalid_item:
                        continue
                    
                    # Now add the sale (after validation passed)
                    db.add(sale)
                    db.flush()  # Get sale.id without committing

                    # Ensure transaction_number exists: if client provided a temp placeholder, replace with stable fallback using real id
                    if getattr(sale, 'transaction_number', '').startswith('temp-'):
                        sale.transaction_number = f"sales#{sale.id}"

                    # Add all sale items
                    for item_data in sale_items_to_add:
                        si = SaleItem(
                            sale_id=sale.id,
                            product_id=item_data['product_id'],
                            quantity=item_data['quantity'],
                            unit_price=item_data['unit_price'],
                            total_price=item_data['total_price']
                        )
                        db.add(si)

                    # Commit everything atomically
                    db.commit()
                    db.refresh(sale)

                    applied.append({'resource_type': 'transaction', 'operation': 'create', 'id': sale.id, 'data': {
                        'transaction_number': sale.transaction_number,
                        'store_id': sale.store_id,
                        'user_id': sale.user_id,
                        'total_amount': sale.total_amount,
                        'payment_method': sale.payment_method
                    }})
                    if ch.temp_id:
                        id_map[ch.temp_id] = sale.id
                        
                elif ch.operation == 'update':
                    if not ch.id:
                        conflicts.append(SyncConflict(resource_type='transaction', id=None, message='Update missing server id').dict())
                        continue
                    sale = db.query(Sale).filter(Sale.id == ch.id).first()
                    if not sale:
                        conflicts.append(SyncConflict(resource_type='transaction', id=ch.id, message='Server record not found').dict())
                        continue
                    data = ch.data or {}
                    for k, v in data.items():
                        if k in ('id', 'items'):  # Never update id (primary key)
                            continue
                        if k == 'transaction_number' and v is None:
                            # Ignore explicit nulls for transaction_number
                            continue
                        if hasattr(sale, k):
                            setattr(sale, k, v)
                    db.commit()
                    db.refresh(sale)
                    applied.append({'resource_type': 'transaction', 'operation': 'update', 'id': sale.id, 'data': {
                        'transaction_number': sale.transaction_number,
                        'store_id': sale.store_id,
                        'user_id': sale.user_id,
                        'total_amount': sale.total_amount,
                        'payment_method': sale.payment_method
                    }})
                    
                else:
                    conflicts.append(SyncConflict(resource_type='transaction', id=ch.id, message='Operation not supported for transaction').dict())
                    continue

            # ANALYTICS EVENTS
            elif ch.resource_type == 'analytics_event':
                if ch.operation == 'create':
                    data = ch.data or {}
                    ae = AnalyticsEvent(
                        event_name=data.get('event_name', 'unknown'),
                        user_id=data.get('user_id'),
                        from_store_id=data.get('from_store_id'),
                        to_store_id=data.get('to_store_id'),
                        duration_ms=data.get('duration_ms'),
                        metadata_json=str(data.get('metadata')) if data.get('metadata') else None,
                        ip_address=data.get('ip_address'),
                        user_agent=data.get('user_agent')
                    )
                    db.add(ae)
                    db.commit()
                    db.refresh(ae)
                    applied.append({'resource_type': 'analytics_event', 'operation': 'create', 'id': ae.id})
                    if ch.temp_id:
                        id_map[ch.temp_id] = ae.id
                else:
                    # Analytics events are typically insert-only, no updates/deletes via sync
                    conflicts.append(SyncConflict(resource_type='analytics_event', id=ch.id, message='Only create operation supported for analytics_event').dict())
                    continue

            # SETTINGS (user_settings, store_settings, system_settings)
            elif ch.resource_type == 'setting':
                data = ch.data or {}
                setting_type = data.get('setting_type', 'user')  # 'user', 'store', or 'system'

                if ch.operation == 'create' or ch.operation == 'update':
                    if setting_type == 'user':
                        user_id = data.get('user_id') or current_user.id
                        # Find or create user settings
                        us = db.query(UserSettings).filter(UserSettings.user_id == user_id).first()
                        if not us:
                            us = UserSettings(user_id=user_id)
                            db.add(us)
                        # Update fields from data
                        for k, v in data.items():
                            if k in ('id', 'setting_type', 'user_id', 'key', 'value'):
                                continue
                            if hasattr(us, k):
                                setattr(us, k, v)
                        # Handle key-value style updates
                        key = data.get('key')
                        value = data.get('value')
                        if key and hasattr(us, key):
                            setattr(us, key, value)
                        db.commit()
                        db.refresh(us)
                        applied.append({'resource_type': 'setting', 'operation': ch.operation, 'id': us.id})
                        if ch.temp_id:
                            id_map[ch.temp_id] = us.id

                    elif setting_type == 'store':
                        store_id = data.get('store_id')
                        if not store_id:
                            conflicts.append(SyncConflict(resource_type='setting', id=None, message='Store setting missing store_id').dict())
                            continue
                        ss = db.query(StoreSettings).filter(StoreSettings.store_id == store_id).first()
                        if not ss:
                            ss = StoreSettings(store_id=store_id)
                            db.add(ss)
                        for k, v in data.items():
                            if k in ('id', 'setting_type', 'store_id', 'key', 'value'):
                                continue
                            if hasattr(ss, k):
                                setattr(ss, k, v)
                        key = data.get('key')
                        value = data.get('value')
                        if key and hasattr(ss, key):
                            setattr(ss, key, value)
                        db.commit()
                        db.refresh(ss)
                        applied.append({'resource_type': 'setting', 'operation': ch.operation, 'id': ss.id})
                        if ch.temp_id:
                            id_map[ch.temp_id] = ss.id

                    elif setting_type == 'system':
                        key = data.get('key')
                        value = data.get('value')
                        if not key:
                            conflicts.append(SyncConflict(resource_type='setting', id=None, message='System setting missing key').dict())
                            continue
                        sys_s = db.query(SystemSettings).filter(SystemSettings.key == key).first()
                        if not sys_s:
                            sys_s = SystemSettings(key=key, value=value)
                            db.add(sys_s)
                        else:
                            sys_s.value = value
                        db.commit()
                        db.refresh(sys_s)
                        applied.append({'resource_type': 'setting', 'operation': ch.operation, 'id': sys_s.id})
                        if ch.temp_id:
                            id_map[ch.temp_id] = sys_s.id
                    else:
                        conflicts.append(SyncConflict(resource_type='setting', id=ch.id, message=f'Unknown setting_type: {setting_type}').dict())
                        continue
                else:
                    conflicts.append(SyncConflict(resource_type='setting', id=ch.id, message='Only create/update operations supported for settings').dict())
                    continue

            else:
                conflicts.append(SyncConflict(resource_type=ch.resource_type, id=ch.id, message='Resource type not supported yet').dict())
                continue

    # Record sync operation metrics
    status = 'success' if not conflicts else 'partial_success' if applied else 'failed'
    record_sync_operation('push', status)

    # Record conflicts if any
    for conflict in conflicts:
        record_sync_conflict('validation_error')

    return SyncPushResponse(applied=applied, conflicts=conflicts, id_map=id_map)
