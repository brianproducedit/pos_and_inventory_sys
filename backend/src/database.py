from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from src.models import Base
import os
from dotenv import load_dotenv

load_dotenv()

# Lazily create engine and ensure it's created with the current DATABASE_URL
_engine = None
_engine_url = None

def _set_sqlite_pragma_on_connect(engine):
    @event.listens_for(engine, "connect")
    def _set_sqlite_pragma(dbapi_connection, connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


def get_engine():
    global _engine, _engine_url
    db_url = os.getenv('DATABASE_URL', 'sqlite:///pos_inventory.db')
    if _engine is None or _engine_url != db_url:
        # (Re)create engine for current DATABASE_URL
        if db_url.startswith('sqlite'):
            _engine = create_engine(db_url, connect_args={"check_same_thread": False})
            _set_sqlite_pragma_on_connect(_engine)
        else:
            _engine = create_engine(db_url)
        # Ensure tables exist for this engine (for tests using create_all fast-path)
        Base.metadata.create_all(bind=_engine)
        _engine_url = db_url
    return _engine

# Provide SessionLocal as a callable factory that always binds to the current engine
def SessionLocal():
    engine = get_engine()
    Session = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    return Session()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()