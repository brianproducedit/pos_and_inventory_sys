from src.database import SessionLocal, get_engine
from src.models import Change
from src.routers.sync import _make_change
import os

print('Testing _make_change function...')

# Set up test database
os.environ['DATABASE_URL'] = 'sqlite:///test_changes.db'

db = SessionLocal()
try:
    # Create a test change
    print('Creating test change...')
    ch_entry = _make_change(db, entity_type='product', entity_id='123', operation='create', payload={'test': 'data'}, origin_client_id='test-client')
    print(f'Created change with server_seq: {ch_entry.server_seq}, id: {ch_entry.id}')

    # Check if it was saved
    count = db.query(Change).count()
    print(f'Total changes in DB: {count}')

    # Check the change
    change = db.query(Change).first()
    if change:
        print(f'Change details: server_seq={change.server_seq}, entity_type={change.entity_type}, operation={change.operation}')

except Exception as e:
    print(f'Error: {e}')
    import traceback
    traceback.print_exc()
finally:
    db.close()