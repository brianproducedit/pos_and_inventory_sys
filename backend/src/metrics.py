"""
Metrics Collection for Monitoring
Provides Prometheus metrics for monitoring sync performance, errors, and system health.
"""
import time
from typing import Optional, Dict, Any
from prometheus_client import Counter, Histogram, Gauge, CollectorRegistry, generate_latest
from fastapi import Request, Response
from fastapi.responses import PlainTextResponse
from starlette.middleware.base import BaseHTTPMiddleware


# Create a custom registry for our metrics
registry = CollectorRegistry()

# Sync-related metrics
SYNC_OPERATIONS_TOTAL = Counter(
    'sync_operations_total',
    'Total number of sync operations',
    ['operation_type', 'status'],
    registry=registry
)

SYNC_DURATION = Histogram(
    'sync_duration_seconds',
    'Time spent on sync operations',
    ['operation_type'],
    buckets=[0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0],
    registry=registry
)

SYNC_CONFLICTS_TOTAL = Counter(
    'sync_conflicts_total',
    'Total number of sync conflicts detected',
    ['conflict_type'],
    registry=registry
)

SYNC_QUEUE_SIZE = Gauge(
    'sync_queue_size',
    'Current size of the sync queue',
    registry=registry
)

# API metrics
API_REQUESTS_TOTAL = Counter(
    'api_requests_total',
    'Total number of API requests',
    ['method', 'endpoint', 'status_code'],
    registry=registry
)

API_REQUEST_DURATION = Histogram(
    'api_request_duration_seconds',
    'API request duration',
    ['method', 'endpoint'],
    buckets=[0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0],
    registry=registry
)

# Database metrics
DB_CONNECTIONS_ACTIVE = Gauge(
    'db_connections_active',
    'Number of active database connections',
    registry=registry
)

DB_QUERY_DURATION = Histogram(
    'db_query_duration_seconds',
    'Database query duration',
    ['query_type'],
    buckets=[0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0],
    registry=registry
)

# Authentication metrics
AUTH_ATTEMPTS_TOTAL = Counter(
    'auth_attempts_total',
    'Total authentication attempts',
    ['result'],
    registry=registry
)

# Error metrics
ERRORS_TOTAL = Counter(
    'errors_total',
    'Total number of errors',
    ['error_type', 'component'],
    registry=registry
)

# Business metrics
ACTIVE_USERS = Gauge(
    'active_users',
    'Number of currently active users',
    registry=registry
)

PRODUCTS_TOTAL = Gauge(
    'products_total',
    'Total number of products in the system',
    registry=registry
)

STORES_TOTAL = Gauge(
    'stores_total',
    'Total number of stores in the system',
    registry=registry
)


class MetricsMiddleware(BaseHTTPMiddleware):
    """FastAPI middleware to collect API metrics"""

    async def dispatch(self, request: Request, call_next):
        start_time = time.time()

        # Extract request info
        method = request.method
        path = request.url.path

        # Process the request
        response = await call_next(request)

        # Record metrics
        API_REQUESTS_TOTAL.labels(
            method=method,
            endpoint=path,
            status_code=response.status_code
        ).inc()

        duration = time.time() - start_time
        API_REQUEST_DURATION.labels(
            method=method,
            endpoint=path
        ).observe(duration)

        return response


def record_sync_operation(operation_type: str, status: str, duration: Optional[float] = None):
    """Record a sync operation"""
    SYNC_OPERATIONS_TOTAL.labels(operation_type=operation_type, status=status).inc()
    if duration is not None:
        SYNC_DURATION.labels(operation_type=operation_type).observe(duration)


def record_sync_conflict(conflict_type: str):
    """Record a sync conflict"""
    SYNC_CONFLICTS_TOTAL.labels(conflict_type=conflict_type).inc()


def update_sync_queue_size(size: int):
    """Update the sync queue size gauge"""
    SYNC_QUEUE_SIZE.set(size)


def record_auth_attempt(result: str):
    """Record an authentication attempt"""
    AUTH_ATTEMPTS_TOTAL.labels(result=result).inc()


def record_error(error_type: str, component: str):
    """Record an error"""
    ERRORS_TOTAL.labels(error_type=error_type, component=component).inc()


def update_business_metrics(users: int = None, products: int = None, stores: int = None):
    """Update business metrics gauges"""
    if users is not None:
        ACTIVE_USERS.set(users)
    if products is not None:
        PRODUCTS_TOTAL.set(products)
    if stores is not None:
        STORES_TOTAL.set(stores)


async def metrics_endpoint() -> PlainTextResponse:
    """Prometheus metrics endpoint"""
    return PlainTextResponse(
        generate_latest(registry),
        media_type="text/plain; charset=utf-8"
    )


# Convenience functions for timing operations
class Timer:
    """Context manager for timing operations"""

    def __init__(self, metric: Histogram, labels: Optional[Dict[str, str]] = None):
        self.metric = metric
        self.labels = labels or {}
        self.start_time = None

    def __enter__(self):
        self.start_time = time.time()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.start_time is not None:
            duration = time.time() - self.start_time
            self.metric.labels(**self.labels).observe(duration)


def time_sync_operation(operation_type: str):
    """Context manager for timing sync operations"""
    return Timer(SYNC_DURATION, {'operation_type': operation_type})


def time_db_query(query_type: str):
    """Context manager for timing database queries"""
    return Timer(DB_QUERY_DURATION, {'query_type': query_type})