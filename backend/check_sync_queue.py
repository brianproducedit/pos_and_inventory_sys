import sqlite3
import os

# Try to find the SQLite database
db_paths = [
    r'C:\Users\k.off\Documents\Programming\Programming Projects\Flutter\pos_and_inventory_sys\pos_inventory.db',
    r'C:\Users\k.off\AppData\Local\Packages\com.example.mobile_app_y1wvscjjxnmeg\LocalState\pos_app.db',
    r'C:\Users\k.off\Documents\pos_app.db',
]

for db_path in db_paths:
    if os.path.exists(db_path):
        print(f'Found database at: {db_path}')
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Get unique table names from sync_queue with status='pending'
        cursor.execute("""
            SELECT DISTINCT table_name, COUNT(*) as count
            FROM sync_queue 
            WHERE status = 'pending'
            GROUP BY table_name
        """)
        
        rows = cursor.fetchall()
        if rows:
            print('\nPending sync queue items by table:')
            for row in rows:
                print(f'  {row[0]}: {row[1]} items')
        else:
            print('\nNo pending sync items found')
        
        # Also check for failed items
        cursor.execute("""
            SELECT DISTINCT table_name, COUNT(*) as count
            FROM sync_queue 
            WHERE status = 'failed'
            GROUP BY table_name
        """)
        
        failed_rows = cursor.fetchall()
        if failed_rows:
            print('\nFailed sync queue items by table:')
            for row in failed_rows:
                print(f'  {row[0]}: {row[1]} items')
        
        conn.close()
        break
else:
    print('Could not find SQLite database in expected locations')
    print('Tried:')
    for path in db_paths:
        print(f'  {path}')
