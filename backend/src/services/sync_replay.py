from sqlalchemy.orm import Session
from typing import Dict, Any, List
from src.models import Change, Product, Store, User, AuditLog


def _apply_product_update(db: Session, ch: Change, dry_run: bool) -> Dict[str, Any]:
    payload = ch.payload or {}
    data = payload.get('data', {})
    if not ch.entity_id:
        return {'status': 'error', 'message': 'Missing entity_id for product update', 'server_seq': ch.server_seq}
    p = db.query(Product).filter(Product.id == int(ch.entity_id)).first()
    if not p:
        return {'status': 'skipped', 'message': f'Product {ch.entity_id} not found', 'server_seq': ch.server_seq}

    # Apply updates
    if dry_run:
        return {'status': 'dry-run', 'message': f'Would update product {ch.entity_id}', 'server_seq': ch.server_seq}

    for k, v in data.items():
        if hasattr(p, k):
            setattr(p, k, v)
    db.commit()
    db.refresh(p)
    return {'status': 'applied', 'message': f'Updated product {ch.entity_id}', 'server_seq': ch.server_seq}


def _apply_product_delete(db: Session, ch: Change, dry_run: bool) -> Dict[str, Any]:
    if not ch.entity_id:
        return {'status': 'error', 'message': 'Missing entity_id for delete', 'server_seq': ch.server_seq}
    p = db.query(Product).filter(Product.id == int(ch.entity_id)).first()
    if not p:
        return {'status': 'skipped', 'message': f'Product {ch.entity_id} not found', 'server_seq': ch.server_seq}
    if dry_run:
        return {'status': 'dry-run', 'message': f'Would delete product {ch.entity_id}', 'server_seq': ch.server_seq}
    p.is_active = False
    db.commit()
    db.refresh(p)
    al = AuditLog(user_id=None, action='REPLAY_DELETE_PRODUCT', resource_type='product', resource_id=p.id, details=f"Replayed delete for server_seq {ch.server_seq}")
    db.add(al)
    db.commit()
    return {'status': 'applied', 'message': f'Deleted (soft) product {ch.entity_id}', 'server_seq': ch.server_seq}


def replay_changes(db: Session, from_seq: int, to_seq: int, dry_run: bool = False, entity_type: str | None = None) -> Dict[str, Any]:
    """Replay changes in server_seq range [from_seq, to_seq]. Returns a report.

    Params:
    - entity_type: optional filter to only replay changes for a specific entity type (e.g., 'product').
    """
    if from_seq is None or to_seq is None:
        raise ValueError('from_seq and to_seq must be provided')
    report: List[Dict[str, Any]] = []
    errors: List[Dict[str, Any]] = []

    q = db.query(Change).filter(Change.server_seq >= from_seq, Change.server_seq <= to_seq).order_by(Change.server_seq.asc())
    if entity_type:
        q = q.filter(Change.entity_type == entity_type)
    rows = q.all()

    for ch in rows:
        try:
            if ch.entity_type == 'product':
                if ch.operation == 'update':
                    # Skip no-op updates where payload matches current state
                    payload = ch.payload or {}
                    data = payload.get('data', {})
                    if ch.entity_id:
                        p = db.query(Product).filter(Product.id == int(ch.entity_id)).first()
                        if p:
                            noop = True
                            for k, v in (data.items() if isinstance(data, dict) else []):
                                if hasattr(p, k) and getattr(p, k) != v:
                                    noop = False
                                    break
                            if noop:
                                report.append({'status': 'skipped', 'message': f'No-op update for product {ch.entity_id}', 'server_seq': ch.server_seq})
                                continue
                    r = _apply_product_update(db, ch, dry_run)
                    report.append(r)
                elif ch.operation == 'delete':
                    # Skip if already deleted / inactive
                    if ch.entity_id:
                        p = db.query(Product).filter(Product.id == int(ch.entity_id)).first()
                        if not p or (p and not p.is_active):
                            report.append({'status': 'skipped', 'message': f'Product {ch.entity_id} already deleted or missing', 'server_seq': ch.server_seq})
                            continue
                    r = _apply_product_delete(db, ch, dry_run)
                    report.append(r)
                elif ch.operation == 'create':
                    # For create, if exists skip; if missing, create a new record using payload.data
                    payload = ch.payload or {}
                    data = payload.get('data', {})
                    if ch.entity_id:
                        existing = db.query(Product).filter(Product.id == int(ch.entity_id)).first()
                        if existing:
                            report.append({'status': 'skipped', 'message': f'Product {ch.entity_id} already exists', 'server_seq': ch.server_seq})
                            continue
                    if dry_run:
                        report.append({'status': 'dry-run', 'message': f'Would create product {ch.entity_id or "<new>"}', 'server_seq': ch.server_seq})
                        continue
                    # Create a new product (id may differ)
                    p = Product(name=data.get('name') or 'Replayed Product', description=data.get('description'), price=data.get('price') or 0.0, stock_quantity=data.get('stock_quantity') or 0, is_active=data.get('is_active', True), store_id=data.get('store_id') or 1)
                    db.add(p)
                    db.commit()
                    db.refresh(p)
                    report.append({'status': 'applied', 'message': f'Created product new_id={p.id} (replay of server_seq {ch.server_seq})', 'server_seq': ch.server_seq})
            else:
                report.append({'status': 'skipped', 'message': f'Entity type {ch.entity_type} not supported for replay yet', 'server_seq': ch.server_seq})
        except Exception as e:
            db.rollback()
            errors.append({'server_seq': ch.server_seq, 'error': str(e)})

    summary = {'from_seq': from_seq, 'to_seq': to_seq, 'dry_run': dry_run, 'entity_type': entity_type, 'processed': len(rows), 'report': report, 'errors': errors}
    # Add simple counts
    applied = sum(1 for r in report if r.get('status') == 'applied')
    skipped = sum(1 for r in report if r.get('status') == 'skipped')
    summary['applied'] = applied
    summary['skipped'] = skipped
    return summary
