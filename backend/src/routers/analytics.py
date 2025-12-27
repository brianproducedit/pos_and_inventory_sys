from fastapi import APIRouter, Depends, Request, HTTPException
from sqlalchemy.orm import Session
from src.schemas import AnalyticsEventCreate, AnalyticsEventResponse
from src.database import get_db
from src.auth import get_current_active_user
from src.models import AnalyticsEvent, User
import json

router = APIRouter()

@router.post('/events', response_model=AnalyticsEventResponse, status_code=201)
async def create_analytics_event(event: AnalyticsEventCreate, request: Request, db: Session = Depends(get_db), current_user: User = Depends(get_current_active_user)):
    # Simple server-side validation
    if not event.event_name:
        raise HTTPException(status_code=400, detail='event_name is required')

    # Record IP and user-agent if not provided
    ip = event.ip_address or request.client.host if request.client else None
    ua = event.user_agent or request.headers.get('user-agent')

    db_event = AnalyticsEvent(
        event_name=event.event_name,
        user_id=current_user.id if current_user else None,
        from_store_id=event.from_store_id,
        to_store_id=event.to_store_id,
        duration_ms=event.duration_ms,
        metadata_json=json.dumps(event.metadata) if event.metadata else None,
        ip_address=ip,
        user_agent=ua,
    )
    db.add(db_event)
    db.commit()
    db.refresh(db_event)

    # Build response payload
    resp = {
        'id': db_event.id,
        'event_name': db_event.event_name,
        'from_store_id': db_event.from_store_id,
        'to_store_id': db_event.to_store_id,
        'duration_ms': db_event.duration_ms,
        'metadata': json.loads(db_event.metadata_json) if db_event.metadata_json else None,
        'ip_address': db_event.ip_address,
        'user_agent': db_event.user_agent,
        'user_id': db_event.user_id,
        'created_at': db_event.created_at,
    }
    return resp


@router.get('/events')
async def list_analytics_events(
    event_name: str | None = None,
    limit: int = 50,
    offset: int = 0,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    # Only superadmin can list analytics events
    from src.models import UserRole
    if current_user.role != UserRole.superadmin:
        raise HTTPException(status_code=403, detail='Access denied: superadmin only')

    query = db.query(AnalyticsEvent)
    if event_name:
        query = query.filter(AnalyticsEvent.event_name == event_name)

    total = query.count()

    events = (
        query.order_by(AnalyticsEvent.created_at.desc()).offset(offset).limit(limit).all()
    )

    results = []
    for e in events:
        results.append({
            'id': e.id,
            'event_name': e.event_name,
            'from_store_id': e.from_store_id,
            'to_store_id': e.to_store_id,
            'duration_ms': e.duration_ms,
            'metadata': json.loads(e.metadata_json) if e.metadata_json else None,
            'ip_address': e.ip_address,
            'user_agent': e.user_agent,
            'user_id': e.user_id,
            'created_at': e.created_at,
        })

    return {'events': results, 'total_count': total}


# Summary endpoint: counts, avg duration, by-store breakdown
@router.get('/summary')
async def analytics_summary(
    event_name: str,
    since_days: int | None = None,
    granularity: str | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    from datetime import datetime, timedelta, date
    from sqlalchemy import func
    from src.models import UserRole

    if current_user.role != UserRole.superadmin:
        raise HTTPException(status_code=403, detail='Access denied: superadmin only')

    query = db.query(AnalyticsEvent).filter(AnalyticsEvent.event_name == event_name)

    # Parse start/end ISO dates if provided
    start_dt = None
    end_dt = None
    if start_date:
        try:
            start_dt = datetime.fromisoformat(start_date).date()
        except Exception:
            raise HTTPException(status_code=400, detail='start_date must be ISO date YYYY-MM-DD')
    if end_date:
        try:
            end_dt = datetime.fromisoformat(end_date).date()
        except Exception:
            raise HTTPException(status_code=400, detail='end_date must be ISO date YYYY-MM-DD')

    if start_dt and end_dt and start_dt > end_dt:
        raise HTTPException(status_code=400, detail='start_date must be <= end_date')

    if start_dt and end_dt:
        # include full days
        query = query.filter(AnalyticsEvent.created_at >= datetime.combine(start_dt, datetime.min.time()))
        query = query.filter(AnalyticsEvent.created_at <= datetime.combine(end_dt, datetime.max.time()))
    elif since_days is not None:
        cutoff = datetime.utcnow() - timedelta(days=since_days)
        query = query.filter(AnalyticsEvent.created_at >= cutoff)

    total = query.count()

    avg_duration = db.query(func.avg(AnalyticsEvent.duration_ms)).filter(AnalyticsEvent.event_name == event_name)
    if start_dt and end_dt:
        avg_duration = avg_duration.filter(AnalyticsEvent.created_at >= datetime.combine(start_dt, datetime.min.time()))
        avg_duration = avg_duration.filter(AnalyticsEvent.created_at <= datetime.combine(end_dt, datetime.max.time()))
    elif since_days is not None:
        avg_duration = avg_duration.filter(AnalyticsEvent.created_at >= cutoff)
    avg_val = avg_duration.scalar()

    # counts grouped by to_store_id within filter
    store_counts = (
        db.query(AnalyticsEvent.to_store_id, func.count(AnalyticsEvent.id))
        .filter(AnalyticsEvent.event_name == event_name)
    )
    if start_dt and end_dt:
        store_counts = store_counts.filter(AnalyticsEvent.created_at >= datetime.combine(start_dt, datetime.min.time()))
        store_counts = store_counts.filter(AnalyticsEvent.created_at <= datetime.combine(end_dt, datetime.max.time()))
    elif since_days is not None:
        store_counts = store_counts.filter(AnalyticsEvent.created_at >= cutoff)
    store_counts = store_counts.group_by(AnalyticsEvent.to_store_id).all()

    by_store = [{'store_id': sc[0], 'count': sc[1]} for sc in store_counts]

    # If daily granularity requested and a date range provided, build per-day series per store
    labels = None
    if granularity == 'daily' and (since_days is not None or (start_dt and end_dt)):
        if start_dt and end_dt:
            first_day = start_dt
            last_day = end_dt
        else:
            # since_days is not None
            first_day = (datetime.utcnow() - timedelta(days=since_days - 1)).date()
            last_day = datetime.utcnow().date()

        days = []
        cur = first_day
        while cur <= last_day:
            days.append(cur)
            cur = cur + timedelta(days=1)
        labels = [d.isoformat() for d in days]

        # prefill series per store
        store_series = {}
        for s in by_store:
            store_series[s['store_id']] = [0] * len(days)

        # Fetch events in range and aggregate in Python
        events_q = db.query(AnalyticsEvent).filter(AnalyticsEvent.event_name == event_name)
        events_q = events_q.filter(AnalyticsEvent.created_at >= datetime.combine(first_day, datetime.min.time()))
        events_q = events_q.filter(AnalyticsEvent.created_at <= datetime.combine(last_day, datetime.max.time()))
        events = events_q.all()

        for e in events:
            day = e.created_at.date().isoformat()
            sid = e.to_store_id
            try:
                idx = labels.index(day)
            except ValueError:
                idx = None
            if idx is not None:
                store_series.setdefault(sid, [0] * len(days))[idx] += 1

        # attach series to by_store entries
        for s in by_store:
            s['series'] = store_series.get(s['store_id'], [0] * len(days))

    resp = {
        'event_name': event_name,
        'total_count': total,
        'avg_duration_ms': float(avg_val) if avg_val is not None else None,
        'by_store': by_store,
    }
    if labels is not None:
        resp['labels'] = labels

    return resp
