from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from src.routers import auth, users, products, sales, inventory, settings, audit, stores, analytics, sync, admin
from src.metrics import MetricsMiddleware, metrics_endpoint, update_business_metrics
from src.feature_flags import feature_flags

import os

app = FastAPI(title="POS and Inventory System API", version="1.0.0")

# Add metrics middleware
app.add_middleware(MetricsMiddleware)

# CORS — controlled via CORS_ORIGINS env var (comma-separated)
_cors_origins = os.getenv("CORS_ORIGINS", "http://localhost:3000,http://localhost:8080").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/auth", tags=["auth"])
# Register stores router BEFORE users router to ensure /api/stores/current matches
# before /api/stores/{store_id} from users router
app.include_router(stores.router, prefix="", tags=["stores"])
app.include_router(users.router, prefix="/api", tags=["users"])
app.include_router(products.router, prefix="/api", tags=["products"])
app.include_router(sales.router, prefix="/api", tags=["sales"])
app.include_router(inventory.router, prefix="/api", tags=["inventory"])
app.include_router(settings.router, prefix="/api/settings", tags=["settings"])
app.include_router(audit.router, prefix="/api", tags=["audit"])
app.include_router(analytics.router, prefix="/api/analytics", tags=["analytics"])
app.include_router(sync.router, prefix="", tags=["sync"])
app.include_router(admin.router, prefix="/api/admin", tags=["admin"])
# Ensure default superadmin exists on startup (dev convenience)
@app.on_event("startup")
async def startup_event():
    # Create or update the default superadmin account; no-op if already correct
    try:
        # Import lazily to avoid import-time issues in some environments
        from src.init_db import create_admin_user
        create_admin_user()
    except ModuleNotFoundError:
        print("Startup admin creation skipped: src.init_db not importable in this environment")
    except Exception as e:
        print(f"Startup admin creation failed: {e}")

@app.get("/")
async def root():
    return {"message": "Welcome to POS and Inventory System API"}

@app.get("/health")
async def health():
    """Healthcheck endpoint for containers and load balancers"""
    return {"status": "ok"}

@app.get("/metrics")
async def get_metrics():
    """Prometheus metrics endpoint"""
    return await metrics_endpoint()

@app.get("/feature-flags")
async def get_feature_flags():
    """Get current feature flags (for debugging/admin purposes)"""
    return {
        "flags": feature_flags.get_all_flags(),
        "enabled_flags": feature_flags.get_enabled_flags()
    }

@app.get("/status")
async def system_status():
    """System status with feature flags and basic metrics"""
    return {
        "status": "ok",
        "version": "1.0.0",
        "features": feature_flags.get_enabled_flags(),
        "timestamp": "2025-12-30"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)