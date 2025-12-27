from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
from .models import UserRole

# Store schemas
class StoreBase(BaseModel):
    name: str
    location: Optional[str] = None
    is_active: bool = True

class StoreCreate(StoreBase):
    pass

class StoreUpdate(BaseModel):
    name: Optional[str] = None
    location: Optional[str] = None
    is_active: Optional[bool] = None

class StoreResponse(StoreBase):
    id: int
    created_by: Optional[int]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

# User schemas
class UserBase(BaseModel):
    username: str
    full_name: Optional[str] = None
    role: UserRole
    is_active: bool = True
    store_id: Optional[int] = None

class UserCreate(UserBase):
    password: str

class UserUpdate(BaseModel):
    username: Optional[str] = None
    full_name: Optional[str] = None
    role: Optional[UserRole] = None
    is_active: Optional[bool] = None
    store_id: Optional[int] = None
    password: Optional[str] = None

class UserResponse(UserBase):
    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

# Product schemas
class ProductBase(BaseModel):
    name: str
    description: Optional[str] = None
    price: float
    stock_quantity: int = 0
    is_active: bool = True

class ProductCreate(ProductBase):
    pass

class ProductUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    price: Optional[float] = None
    stock_quantity: Optional[int] = None
    is_active: Optional[bool] = None

class ProductResponse(ProductBase):
    id: int
    store_id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

# Sale schemas
class SaleItemBase(BaseModel):
    product_id: int
    quantity: int
    unit_price: float

class SaleItemCreate(SaleItemBase):
    pass

class SaleItemResponse(SaleItemBase):
    id: int
    sale_id: int
    total_price: float

    class Config:
        from_attributes = True

class SaleBase(BaseModel):
    total_amount: float
    payment_method: Optional[str] = None
    paynow_reference: Optional[str] = None
    status: str = "completed"

class SaleCreate(SaleBase):
    items: List[SaleItemCreate]

class SaleResponse(SaleBase):
    id: int
    user_id: int
    store_id: int
    created_at: datetime
    items: List[SaleItemResponse]

    class Config:
        from_attributes = True

# Inventory schemas
class InventoryLogBase(BaseModel):
    product_id: int
    quantity_change: int
    reason: str

class InventoryLogCreate(InventoryLogBase):
    pass

class InventoryLogResponse(InventoryLogBase):
    id: int
    user_id: int
    created_at: datetime

    class Config:
        from_attributes = True

# Authentication schemas
class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    username: Optional[str] = None

class LoginRequest(BaseModel):
    username: str
    password: str

# Audit schemas
from typing import Any

class AuditLogBase(BaseModel):
    action: str
    entity_type: str
    entity_id: Optional[int] = None
    details: Optional[Any] = None
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None

class AuditLogResponse(AuditLogBase):
    id: int
    user_id: Optional[int] = None
    store_id: Optional[int] = None
    timestamp: datetime

    class Config:
        from_attributes = True


class AuditLogListResponse(BaseModel):
    logs: List[AuditLogResponse]
    total_count: int

    class Config:
        from_attributes = True

# Analytics schemas
class AnalyticsEventCreate(BaseModel):
    event_name: str
    from_store_id: Optional[int] = None
    to_store_id: Optional[int] = None
    duration_ms: Optional[int] = None
    metadata: Optional[dict] = None
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None

class AnalyticsEventResponse(AnalyticsEventCreate):
    id: int
    user_id: Optional[int] = None
    created_at: datetime

    class Config:
        from_attributes = True

class AnalyticsSummaryByStore(BaseModel):
    store_id: Optional[int]
    count: int
    series: Optional[List[int]] = None

class AnalyticsSummaryResponse(BaseModel):
    event_name: str
    total_count: int
    avg_duration_ms: Optional[float] = None
    by_store: List[AnalyticsSummaryByStore]
    labels: Optional[List[str]] = None  # e.g., day labels for series

    class Config:
        from_attributes = True