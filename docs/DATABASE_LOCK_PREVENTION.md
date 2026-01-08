# Database Lock Prevention Guide

This document describes the comprehensive measures implemented to prevent SQLite database locks in the POS system.

## Problem Background

The app uses two database access methods:
1. **Drift ORM** - Primary database access for most operations
2. **Raw sqflite** - Used in sync operations for complex transactions

Both access the same `app.sqlite` file. Without proper configuration and coordination, concurrent access can cause "database is locked" errors.

## Architecture Overview

```
Main App (Isolate 1)                 Background Worker (Isolate 2)
├── SyncProvider                     ├── WorkManager
│   └── PostgresSyncService          │   └── SyncWorker
│       ├── Static _isSyncing lock   │       ├── Static _isSyncing lock
│       └── db.database (raw)        │       └── db (Drift)
│                                    │
├── Repositories (Drift)             └── background_sync_service.dart
│   └── db.transaction()                 └── callbackDispatcher()
│
└── UI Providers
    └── Read operations (Drift)
```

**Note:** Static locks are **not shared** between isolates. Cross-isolate protection comes from WAL mode + busy_timeout.

## Prevention Measures

### 1. WAL (Write-Ahead Logging) Mode

**Location:** `app_database.dart` and `sync_database_helper.dart`

WAL mode allows:
- Multiple readers concurrently
- Readers don't block writers (and vice versa)
- Better performance for read-heavy workloads

```dart
await db.customStatement('PRAGMA journal_mode=WAL');
```

### 2. Busy Timeout (30 seconds)

**Location:** `app_database.dart` and `sync_database_helper.dart`

If the database is locked, SQLite will retry for up to 30 seconds before failing:

```dart
await db.customStatement('PRAGMA busy_timeout=30000');
```

### 3. Single Instance Database Connection

**Location:** `sync_database_helper.dart`

The raw sqflite connection uses `singleInstance: true` to ensure only one connection is created:

```dart
_rawDb = await sqflite.openDatabase(
  path,
  singleInstance: true,  // Critical for lock prevention
  ...
);
```

### 4. Static Sync Lock (PostgresSyncService)

**Location:** `postgres_sync_service.dart`

A static boolean lock prevents concurrent sync operations within the main app:

```dart
static bool _isSyncing = false;
static DateTime? _lockAcquiredAt;
static String? _currentOperation;

static Future<bool> _acquireSyncLock({String? operation}) async {
  // Check for stale lock and release if necessary
  if (_isLockStale()) {
    forceReleaseStaleLock();
  }
  if (_isSyncing) return false;
  _isSyncing = true;
  _lockAcquiredAt = DateTime.now();
  _currentOperation = operation;
  return true;
}
```

### 5. Static Sync Lock (SyncWorker)

**Location:** `sync_worker.dart`

Background sync worker has its own static lock for intra-isolate protection:

```dart
static bool _isSyncing = false;
static DateTime? _lockAcquiredAt;
```

### 6. Stale Lock Detection & Auto-Recovery

**Location:** `postgres_sync_service.dart`

If a sync operation holds the lock for > 5 minutes, it's considered stale and will be auto-released:

```dart
static const Duration _maxLockDuration = Duration(minutes: 5);

static bool _isLockStale() {
  if (!_isSyncing || _lockAcquiredAt == null) return false;
  return DateTime.now().difference(_lockAcquiredAt!) > _maxLockDuration;
}
```

### 7. Lock Status Debugging

**Location:** `postgres_sync_service.dart`

Detailed lock status can be retrieved for debugging:

```dart
static SyncLockStatus getLockStatus() {
  return SyncLockStatus(
    isSyncing: _isSyncing,
    lockAcquiredAt: _lockAcquiredAt,
    currentOperation: _currentOperation,
  );
}
```

### 8. Operation-Specific Logging

Each sync method logs when it acquires/releases the lock with operation name:

```
🔒 Sync lock acquired for: performInitialSync
🔓 Sync lock released (held for 2345ms by performInitialSync)
```

### 9. Timeout Protection

**Location:** `postgres_sync_service.dart`

Database operations have a 60-second timeout to prevent indefinite hangs:

```dart
static const Duration _dbTimeout = Duration(seconds: 60);

Future<T> _withDbTimeout<T>(Future<T> Function() operation, ...) async {
  return await operation().timeout(_dbTimeout, ...);
}
```

### 10. No Redundant Database Checks

**Location:** `sync_provider.dart`

Removed redundant `db.database` checks that could open unnecessary connections:

```dart
// BAD - Opens raw sqflite connection just to check
final db = await _syncDbHelper.database;
if (!db.isOpen) return;

// GOOD - Let sync service handle database checks internally
await _syncService.syncPendingChangesBatch();
```

## Diagnostic API

### Check Lock Status

```dart
final status = PostgresSyncService.getLockStatus();
print('Is syncing: ${status.isSyncing}');
print('Lock acquired at: ${status.lockAcquiredAt}');
print('Current operation: ${status.currentOperation}');
```

### Check Database Health

```dart
final health = await getDatabaseLockStatus(db);
print('Journal mode: ${health['journal_mode']}');  // Should be 'wal'
print('Busy timeout: ${health['busy_timeout']}');   // Should be 30000
```

### Force Release Stale Lock (Emergency)

```dart
PostgresSyncService.forceReleaseStaleLock();
```

## Best Practices for Future Development

1. **Never bypass the sync lock** - Always use sync methods that acquire the lock
2. **Keep transactions short** - Don't make HTTP calls inside transactions
3. **Use Drift for normal operations** - Only use raw sqflite when absolutely necessary
4. **Test with concurrent operations** - Verify lock behavior under load
5. **Monitor lock duration** - Check logs for unexpectedly long lock hold times
6. **Don't open database connections unnecessarily** - Each `db.database` call could create conflicts
7. **HTTP calls BEFORE transactions** - Always make network requests before starting database transactions

## Files Modified

- `lib/db/app_database.dart` - Added `configureDatabaseForConcurrency()` and `getDatabaseLockStatus()`
- `lib/data/sync/sync_database_helper.dart` - Added WAL mode, busy timeout, singleInstance, closeRawDatabase()
- `lib/data/sync/postgres_sync_service.dart` - Enhanced lock tracking, timeout, stale detection, SyncLockStatus class
- `lib/providers/sync_provider.dart` - Removed redundant database check that could cause issues
- `lib/services/sync_worker.dart` - Added static lock with timestamp tracking
- `lib/main.dart` - Call `configureDatabaseForConcurrency()` on startup
- `lib/sync/sync_background.dart` - Configure database for background sync
- `lib/services/background_sync_service.dart` - Configure database for WorkManager sync
