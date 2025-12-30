from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, ForeignKey, Text, Enum, Boolean, JSON
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
import enum
from datetime import datetime

Base = declarative_base()

class UserRole(enum.Enum):
    superadmin = "superadmin"
    admin = "admin"
    cashier = "cashier"

class Store(Base):
    __tablename__ = "stores"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    location = Column(String)
    is_active = Column(Boolean, default=True)
    created_by = Column(Integer, ForeignKey("users.id"))
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    creator = relationship("User", foreign_keys=[created_by], backref="created_stores")
    users = relationship("User", back_populates="store", foreign_keys="User.store_id")
    products = relationship("Product", back_populates="store")
    sales = relationship("Sale", back_populates="store")

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, nullable=False)
    password_hash = Column(String, nullable=False)
    full_name = Column(String)
    role = Column(Enum(UserRole), nullable=False)
    is_active = Column(Boolean, default=True)
    store_id = Column(Integer, ForeignKey("stores.id"), nullable=True)  # Null for superadmin
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    store = relationship("Store", back_populates="users", foreign_keys=[store_id])
    sales = relationship("Sale", back_populates="user")
    # Flags
    must_change_password = Column(Boolean, default=False)  # Set True for seeded superadmin to force password change on first login

# Mapping table for assigning users to multiple stores (admins)
class UserStore(Base):
    __tablename__ = "user_stores"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    store_id = Column(Integer, ForeignKey("stores.id"), nullable=False)

    # Relationships
    user = relationship("User", backref="assigned_stores")
    store = relationship("Store", backref="assigned_users")

class Product(Base):
    __tablename__ = "products"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    description = Column(Text)
    price = Column(Float, nullable=False)
    stock_quantity = Column(Integer, default=0)
    is_active = Column(Boolean, default=True)  # New field for soft delete
    store_id = Column(Integer, ForeignKey("stores.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    store = relationship("Store", back_populates="products")
    sale_items = relationship("SaleItem", back_populates="product")
    inventory_logs = relationship("InventoryLog", back_populates="product")

class Sale(Base):
    __tablename__ = "sales"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    store_id = Column(Integer, ForeignKey("stores.id"), nullable=False)
    total_amount = Column(Float, nullable=False)
    payment_method = Column(String)  # e.g., cash, paynow
    paynow_reference = Column(String)  # For Paynow transactions
    status = Column(String, default="completed")  # completed, pending, failed
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    user = relationship("User", back_populates="sales")
    store = relationship("Store", back_populates="sales")
    items = relationship("SaleItem", back_populates="sale")

class SaleItem(Base):
    __tablename__ = "sale_items"
    id = Column(Integer, primary_key=True, index=True)
    sale_id = Column(Integer, ForeignKey("sales.id"), nullable=False)
    product_id = Column(Integer, ForeignKey("products.id"), nullable=False)
    quantity = Column(Integer, nullable=False)
    unit_price = Column(Float, nullable=False)
    total_price = Column(Float, nullable=False)

    # Relationships
    sale = relationship("Sale", back_populates="items")
    product = relationship("Product", back_populates="sale_items")

class InventoryLog(Base):
    __tablename__ = "inventory_logs"
    id = Column(Integer, primary_key=True, index=True)
    product_id = Column(Integer, ForeignKey("products.id"), nullable=False)
    quantity_change = Column(Integer, nullable=False)  # Positive for restock, negative for sale
    reason = Column(String, nullable=False)  # e.g., sale, restock, adjustment
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    product = relationship("Product", back_populates="inventory_logs")
    user = relationship("User")

# For sync: Add version columns if needed, but start simple

class StoreSettings(Base):
    __tablename__ = "store_settings"
    id = Column(Integer, primary_key=True, index=True)
    store_id = Column(Integer, ForeignKey("stores.id"), nullable=False)
    business_name = Column(String)
    address = Column(Text)
    phone = Column(String)
    email = Column(String)
    tax_number = Column(String)
    receipt_footer = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    store = relationship("Store", backref="settings")

class UserSettings(Base):
    __tablename__ = "user_settings"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    theme = Column(String, default='light')
    language = Column(String, default='en')
    notifications_enabled = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    user = relationship("User", backref="settings")

class SystemSettings(Base):
    __tablename__ = "system_settings"
    id = Column(Integer, primary_key=True, index=True)
    key = Column(String, unique=True, nullable=False)
    value = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class AuditLog(Base):
    __tablename__ = "audit_logs"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    store_id = Column(Integer, ForeignKey("stores.id"), nullable=True)
    action = Column(String, nullable=False)  # e.g., "CREATE_USER", "UPDATE_STORE", "DELETE_PRODUCT"
    resource_type = Column(String, nullable=False)  # e.g., "user", "store", "product", "sale"
    resource_id = Column(Integer, nullable=True)  # ID of the affected resource
    details = Column(Text)  # JSON string with additional details
    ip_address = Column(String)
    user_agent = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    user = relationship("User", backref="audit_logs")
    store = relationship("Store", backref="audit_logs")

class Change(Base):
    """Append-only change log for sync.

    Entries are monotonically ordered by `server_seq` which can be used by
    clients as a checkpoint token when pulling changes.
    """
    __tablename__ = "changes"
    id = Column(Integer, primary_key=True, index=True)
    server_seq = Column(Integer, nullable=False, unique=True, index=True)
    entity_type = Column(String, nullable=False)
    entity_id = Column(String, nullable=True)
    operation = Column(String, nullable=False)  # 'create' | 'update' | 'delete'
    payload = Column(JSON)
    client_temp_id = Column(String, nullable=True)
    origin_client_id = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class AnalyticsEvent(Base):
    __tablename__ = "analytics_events"
    id = Column(Integer, primary_key=True, index=True)
    event_name = Column(String, nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    from_store_id = Column(Integer, ForeignKey("stores.id"), nullable=True)
    to_store_id = Column(Integer, ForeignKey("stores.id"), nullable=True)
    duration_ms = Column(Integer, nullable=True)
    metadata_json = Column(Text)
    ip_address = Column(String)
    user_agent = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    user = relationship("User", backref="analytics_events")
    from_store = relationship("Store", foreign_keys=[from_store_id])
    to_store = relationship("Store", foreign_keys=[to_store_id])