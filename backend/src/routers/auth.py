from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from src.database import get_db
from src.auth import authenticate_user, create_access_token
from src.audit_service import AuditService, AUDIT_ACTIONS
from datetime import timedelta
from pydantic import BaseModel

router = APIRouter()

class Token(BaseModel):
    access_token: str
    token_type: str

@router.post("/token", response_model=Token)
async def login_for_access_token(
    form_data: OAuth2PasswordRequestForm = Depends(),
    request: Request = None,
    db: Session = Depends(get_db)
):
    # Debugging: log attempt and client info
    print(f"Login attempt for username='{form_data.username}' from {request.client.host if request and request.client else 'unknown host'}")

    user = authenticate_user(db, form_data.username, form_data.password)
    if not user:
        # Log failed login attempt
        print(f"Failed login for username='{form_data.username}'")
        audit_service = AuditService(db)
        audit_service.log_activity(
            user_id=None,  # No user ID for failed login
            action=AUDIT_ACTIONS["FAILED_LOGIN"],
            resource_type="auth",
            resource_id=None,
            details={
                "username_attempted": form_data.username,
                "login_method": "password"
            },
            ip_address=request.client.host if request and request.client else None,
            user_agent=request.headers.get("user-agent") if request else None
        )
        raise HTTPException(status_code=400, detail="Incorrect username or password")
    else:
        print(f"Successful login for username='{form_data.username}', user_id={user.id}")
    
    # Log successful login
    audit_service = AuditService(db)
    audit_service.log_activity(
        user_id=user.id,
        action=AUDIT_ACTIONS["LOGIN"],
        resource_type="auth",
        resource_id=user.id,
        details={
            "username": user.username,
            "user_role": user.role.value,
            "store_id": user.store_id,
            "login_method": "password"
        },
        ip_address=request.client.host if request and request.client else None,
        user_agent=request.headers.get("user-agent") if request else None
    )
    
    access_token_expires = timedelta(minutes=30)
    access_token = create_access_token(
        data={"sub": user.username}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}