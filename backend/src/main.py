from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from src.routers import auth, users, products, sales, inventory, settings, audit, stores, analytics, sync, admin

app = FastAPI(title="POS and Inventory System API", version="1.0.0")

# CORS for Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Change in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(users.router, prefix="/api", tags=["users"])
app.include_router(products.router, prefix="/api", tags=["products"])
app.include_router(sales.router, prefix="/api", tags=["sales"])
app.include_router(inventory.router, prefix="/api", tags=["inventory"])
app.include_router(settings.router, prefix="/api/settings", tags=["settings"])
app.include_router(audit.router, prefix="/api", tags=["audit"])
app.include_router(analytics.router, prefix="/api/analytics", tags=["analytics"])
app.include_router(stores.router, prefix="", tags=["stores"])
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

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)