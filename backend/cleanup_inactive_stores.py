"""One-off script to hard-delete all inactive stores and their related data.
Run from backend directory with the project's venv active:

python cleanup_inactive_stores.py

"""
from src.database import SessionLocal
from src.models import Store
from src.store_utils import hard_delete_store


def main():
    db = SessionLocal()
    try:
        inactive_stores = db.query(Store).filter(Store.is_active == False).all()
        print(f"Found {len(inactive_stores)} inactive stores to delete")
        for store in inactive_stores:
            print(f"Hard deleting store id={store.id}, name={store.name}")
            try:
                result = hard_delete_store(db, store.id)
                print(result)
            except Exception as e:
                print(f"Failed to delete store id={store.id}: {e}")
    finally:
        db.close()


if __name__ == '__main__':
    main()
