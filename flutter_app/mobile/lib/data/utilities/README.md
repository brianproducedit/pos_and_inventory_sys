# Database Cleanup Tools

This directory contains utilities to clean up duplicate and orphaned records in both the mobile SQLite database and the PostgreSQL backend.

## Mobile App Cleanup (Flutter/Dart)

### Using the UI (Recommended)

1. Navigate to the **Sync Demo** screen in the mobile app
2. Scroll to find the **🧹 Clean Database** button
3. Click to run the cleanup - you'll see a confirmation dialog
4. The cleanup will remove:
   - Duplicate products (same name in same store)
   - Duplicate users (same username)
   - Orphaned products (referencing non-existent stores)
   - Orphaned sync queue items

### Programmatic Usage

```dart
import 'package:mobile/data/utilities/database_cleanup.dart';
import 'package:mobile/db/app_database.dart';

// Get database instance
final db = context.read<AppDatabase>();
final cleanup = DatabaseCleanup(db);

// Run all cleanup operations
final results = await cleanup.cleanupAll();
print('Deleted ${results.values.reduce((a, b) => a + b)} total records');

// Or run specific cleanups
await cleanup.cleanupDuplicateProducts();
await cleanup.cleanupOrphanedProducts();
await cleanup.cleanupDuplicateUsers();
await cleanup.cleanupOrphanedSyncQueue();

// Get database statistics
final stats = await cleanup.getDatabaseStats();
print('Total products: ${stats['total_products']}');
print('Unsynced products: ${stats['unsynced_products']}');
print('Orphaned products: ${stats['orphaned_products']}');
```

## Backend Database Check (Python)

### Check Database Health

Run this script to check for duplicates and inconsistencies in the PostgreSQL database:

```bash
cd backend
python scripts/check_database_health.py
```

This will show:
- Database statistics (total products, users, stores)
- Duplicate products (same name in same store)
- Duplicate users (same username)
- Orphaned products (referencing non-existent stores)
- Orphaned users (referencing non-existent stores)

### Sample Output

```
============================================================
🧹 Database Cleanup Check
============================================================

📊 Database Statistics:
  Products: 45 total, 42 active
  Users: 8 total, 7 active
  Stores: 1 total, 1 active

  Active Stores:
    - id=24, name='Test Store - Online', products=42, users=7

🔍 Checking for duplicate products...
  ✅ No duplicate products found

🔍 Checking for duplicate users...
  ✅ No duplicate users found

🔍 Checking for orphaned products...
  ✅ No orphaned products found

🔍 Checking for orphaned users...
  ✅ No orphaned users found

============================================================
✅ Check complete!
============================================================
```

## Common Issues and Solutions

### Issue: Products showing twice in mobile app

**Cause**: Sync created duplicate records, or server response created a new record instead of updating existing one.

**Solution**:
1. Run mobile cleanup: Use the **🧹 Clean Database** button in Sync Demo screen
2. This will keep the product with a server_id and delete local-only duplicates

### Issue: FK constraint failed for products/users

**Cause**: Product/user references a store_id that doesn't exist locally (server_id vs local_id mismatch).

**Solution**:
1. Ensure all stores are synced to the mobile device first
2. Log out and log back in to trigger a full initial sync
3. Run the cleanup to remove orphaned records

### Issue: Products not syncing to server

**Cause**: Product references a store that hasn't been synced to server yet.

**Solution**:
1. The sync service now automatically defers product sync until stores are synced
2. Check sync queue status in the Sync Demo screen
3. Trigger manual sync after ensuring stores exist on server

## Prevention

The sync code has been updated to:
- Map server store_id → local store_id when receiving data from server
- Map local store_id → server store_id when sending data to server
- Skip updates for products/users when store doesn't exist locally
- Defer product creation until referenced stores are synced

These changes should prevent most duplicate and orphaned record issues going forward.
