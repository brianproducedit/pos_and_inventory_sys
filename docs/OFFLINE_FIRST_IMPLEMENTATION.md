# Offline-First Implementation Guide

## Overview

This guide documents the implementation of the V2 offline-first architecture for the POS & Inventory System. It covers architecture decisions, code patterns, and best practices.

## Architecture

### Core Principles

1. **Local-First Data Storage** - All data operations go to Drift/SQLite first
2. **Background Sync** - Changes sync to server asynchronously
3. **Conflict Detection** - Server is source of truth for conflicts
4. **Graceful Degradation** - Full functionality without internet

### Component Layers

```
┌─────────────────────────────────────┐
│          UI Layer (Widgets)         │
│  home_screen, pos_screen, etc.      │
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│     State Management (Providers)    │
│  CartProvider, AuthProvider, etc.   │
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│    Repository Layer (V2 Repos)      │
│  UserRepo, ProductRepo, SaleRepo    │
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│    Database Layer (Drift/SQLite)    │
│        AppDatabase (local)          │
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│      Sync Layer (SyncWorker)        │
│   Push/Pull, Conflict Resolution    │
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│     API Layer (ApiClient)           │
│    REST calls to FastAPI backend    │
└─────────────────────────────────────┘
```

## Database Schema

### Sync Metadata

All tables include these sync-related columns:

```dart
IntColumn get id => integer().autoIncrement()();
TextColumn get clientId => text().withDefault(const Constant(''))();
IntColumn get serverId => integer().nullable()();
TextColumn get syncStatus => text().map(syncStatusConverter)
    .withDefault(Constant(SyncStatus.pending.name))();
DateTimeColumn get lastUpdatedAt => dateTime().withDefault(currentDateAndTime)();
DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
```

**Field Purposes:**
- `id` - Local auto-increment primary key
- `clientId` - UUID for temp identification before sync
- `serverId` - Server-assigned ID after sync (nullable)
- `syncStatus` - Enum: `synced`, `pending`, `conflict`, `error`
- `lastUpdatedAt` - For conflict resolution (newest wins)
- `createdAt` - Creation timestamp

### Key Tables

#### Users
```dart
class Users extends Table {
  // Sync metadata (above)
  TextColumn get username => text()();
  TextColumn get passwordHash => text()(); // For offline auth
  TextColumn get fullName => text().nullable()();
  TextColumn get role => text().map(userRoleConverter)();
  IntColumn get storeId => integer().nullable()();
  BoolColumn get isActive => boolean()();
  BoolColumn get isLocalOnly => boolean()(); // Ghost users
}
```

#### Products
```dart
class Products extends Table {
  // Sync metadata
  TextColumn get name => text()();
  TextColumn get sku => text().nullable()();
  RealColumn get price => real()();
  IntColumn get stockQuantity => integer()();
  BoolColumn get isActive => boolean()();
  IntColumn get storeId => integer().references(Stores, #id)();
}
```

#### Sales
```dart
class Sales extends Table {
  // Sync metadata
  TextColumn get transactionNumber => text()();
  IntColumn get userId => integer().references(Users, #id)();
  IntColumn get storeId => integer().references(Stores, #id)();
  RealColumn get totalAmount => real()();
  TextColumn get paymentMethod => text()();
}
```

### Sync Queue

Tracks all pending changes:

```dart
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get resourceType => text()(); // 'user', 'product', 'sale'
  IntColumn get resourceId => integer()(); // Local ID
  TextColumn get operation => text()(); // 'create', 'update', 'delete'
  TextColumn get payload => text()(); // JSON data
  TextColumn get status => text()(); // 'pending', 'processing', 'failed'
  IntColumn get retryCount => integer()();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}
```

## Repository Pattern

### Base Pattern

All V2 repositories follow this pattern:

```dart
class EntityRepository {
  final AppDatabase db;

  // CREATE - Always local-first
  Future<int> create(params) async {
    final id = await db.into(db.entities).insert(companion);
    await _enqueueSyncOperation(id, 'create', data);
    return id;
  }

  // READ - Always from local DB
  Future<Entity?> getById(int id) async {
    return (db.select(db.entities)..where((e) => e.id.equals(id)))
        .getSingleOrNull();
  }

  // UPDATE - Local update + sync queue
  Future<void> update(int id, params) async {
    await (db.update(db.entities)..where((e) => e.id.equals(id)))
        .write(companion);
    await _enqueueSyncOperation(id, 'update', data);
  }

  // DELETE - Soft delete + sync queue
  Future<void> delete(int id) async {
    await (db.update(db.entities)..where((e) => e.id.equals(id)))
        .write(EntitiesCompanion(isActive: Value(false)));
    await _enqueueSyncOperation(id, 'delete', {});
  }

  // SYNC HELPERS
  Future<void> _enqueueSyncOperation(int id, String operation, Map data) async {
    await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
      resourceType: 'entity',
      resourceId: id,
      operation: operation,
      payload: Value(jsonEncode(data)),
    ));
  }

  Future<void> markAsSynced(int id, {required int serverId}) async {
    await (db.update(db.entities)..where((e) => e.id.equals(id)))
        .write(EntitiesCompanion(
          serverId: Value(serverId),
          syncStatus: Value(SyncStatus.synced),
        ));
  }
}
```

### Key Principles

1. **All writes go to local DB first** - Never wait for network
2. **Enqueue every change** - Background sync handles upload
3. **Reads are always local** - Fast and reliable
4. **Soft deletes** - Mark as inactive, sync deletion

## Authentication Flow

### Ghost User Pattern

When offline, users can still "login" by creating a ghost user:

```dart
// OfflineAuthService.login()
if (networkAvailable) {
  // 1. Try online login
  final response = await apiClient.login(username, password);
  
  // 2. Cache credentials locally
  await _cacheUser(response['user'], password);
  
  return LoginResult(success: true, isOffline: false);
} else {
  // 3. Check cached credentials
  final cachedUser = await userRepo.getByUsername(username);
  
  if (cachedUser != null && await _validatePassword(cachedUser, password)) {
    return LoginResult(success: true, isOffline: true);
  }
  
  // 4. Create ghost user if new
  final ghostUserId = await userRepo.create(
    username: username,
    password: password,
    isLocalOnly: true, // Marked as ghost
  );
  
  return LoginResult(success: true, isOffline: true, isGhost: true);
}
```

**Ghost User Characteristics:**
- `isLocalOnly = true`
- `syncStatus = pending`
- `serverId = null`
- Will sync to server when online

### Password Hashing

Passwords hashed locally for offline validation:

```dart
import 'package:crypto/crypto.dart';
import 'dart:convert';

String hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

bool validatePassword(User user, String password) {
  return user.passwordHash == hashPassword(password);
}
```

## Sync Engine

### Sync Workflow

```
┌────────────────┐
│  Trigger Sync  │
└────────┬───────┘
         │
    ┌────▼─────┐
    │  Push    │ ← Upload pending changes
    └────┬─────┘
         │
    ┌────▼─────┐
    │  Pull    │ ← Download server changes
    └────┬─────┘
         │
    ┌────▼─────┐
    │  Resolve │ ← Handle conflicts
    └──────────┘
```

### Push Phase

```dart
Future<void> _pushChanges() async {
  // 1. Get pending items from queue (batch of 100)
  final items = await db.getPendingChanges();
  
  for (final item in items) {
    try {
      // 2. Call appropriate API endpoint
      final response = await _syncItem(item);
      
      // 3. Update local record with server ID
      await _updateServerId(item.resourceId, response['id']);
      
      // 4. Mark as synced in queue
      await db.deleteQueueItem(item.id);
      
    } catch (e) {
      // 5. Mark for retry with exponential backoff
      await _markForRetry(item.id, e.toString());
    }
  }
}
```

### Pull Phase

```dart
Future<void> _pullChanges() async {
  // 1. Get last sync timestamp
  final lastSync = await _getLastSyncTime();
  
  // 2. Fetch changes since last sync
  final changes = await apiClient.pullChanges(since: lastSync);
  
  for (final change in changes['changes']) {
    // 3. Check for conflicts
    if (await _hasConflict(change)) {
      await _createConflictRecord(change);
      continue;
    }
    
    // 4. Apply change to local DB
    await _applyChange(change);
  }
  
  // 5. Update sync timestamp
  await _saveLastSyncTime(DateTime.now());
}
```

### Conflict Resolution

**Detection:**
```dart
bool _hasConflict(Map serverChange) {
  final localItem = await db.getByServerId(serverChange['id']);
  
  if (localItem == null) return false;
  
  // Conflict if local has pending changes and server is newer
  return localItem.syncStatus == SyncStatus.pending &&
         serverChange['updated_at'] > localItem.lastUpdatedAt;
}
```

**Resolution Strategies:**
1. **Keep Local** - Discard server version, keep local changes
2. **Use Server** - Discard local changes, accept server version
3. **Merge** - Combine both (field-level merge)
4. **Manual** - User decides via UI

## Offline Operations

### Create Sale Offline

```dart
// SaleRepository.createSale()
Future<int> createSale({
  required int userId,
  required int storeId,
  required List<SaleItemData> items,
  required double totalAmount,
  required String paymentMethod,
}) async {
  return await db.transaction(() async {
    // 1. Create sale record
    final saleId = await db.into(db.sales).insert(
      SalesCompanion.insert(
        clientId: Value(uuid.v4()),
        transactionNumber: _generateTransactionNumber(),
        userId: userId,
        storeId: storeId,
        totalAmount: totalAmount,
        paymentMethod: paymentMethod,
        syncStatus: Value(SyncStatus.pending),
      ),
    );
    
    // 2. Create sale items
    for (final item in items) {
      await db.into(db.saleItems).insert(
        SaleItemsCompanion.insert(
          saleId: saleId,
          productId: item.productId,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
        ),
      );
      
      // 3. Deduct stock
      await _deductStock(item.productId, item.quantity);
    }
    
    // 4. Enqueue for sync
    await _enqueueSyncOperation(saleId, 'create', {...});
    
    return saleId;
  });
}
```

**Key Points:**
- Atomic transaction ensures consistency
- Stock deducted immediately (no overselling)
- All changes queued for sync
- Works identically online/offline

### Search Products Offline

```dart
Future<List<Product>> search(String query) async {
  final normalized = query.toLowerCase();
  
  return (db.select(db.products)
    ..where((p) => 
        p.name.lower().like('%$normalized%') |
        p.sku.lower().like('%$normalized%'))
    ..where((p) => p.isActive.equals(true))
    ..orderBy([(p) => OrderingTerm.asc(p.name)]))
    .get();
}
```

**Optimization:**
- Uses indexed columns (name, SKU)
- Case-insensitive search
- Filters inactive products
- Fast even with 10,000+ products

## Background Sync

### WorkManager Integration

```dart
// BackgroundSyncService
Future<void> registerPeriodicSync() async {
  await Workmanager().registerPeriodicTask(
    'sync-task',
    'backgroundSync',
    frequency: Duration(minutes: 15),
    constraints: Constraints(
      networkType: isWifiOnly ? NetworkType.unmetered : NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
  );
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final db = await AppDatabase.open();
    final syncWorker = SyncWorker(db: db, ...);
    
    await syncWorker.triggerSync();
    
    return true;
  });
}
```

### Sync Frequency

- **Foreground:** Immediate on network reconnection
- **Background:** Every 15 minutes (WorkManager)
- **Manual:** Pull-to-refresh in UI
- **On Login:** Immediate full sync

## Testing Strategy

### Unit Tests

Test repositories in isolation:

```dart
test('create should enqueue sync operation', () async {
  final db = AppDatabase.memory();
  final repo = ProductRepository(db);
  
  final productId = await repo.create(
    name: 'Test Product',
    price: 10.00,
    storeId: 1,
  );
  
  final syncItems = await db.getPendingChanges();
  expect(syncItems.length, 1);
  expect(syncItems.first.resourceType, 'product');
  expect(syncItems.first.operation, 'create');
});
```

### Integration Tests

Test sync engine:

```dart
test('should sync pending changes to server', () async {
  final db = AppDatabase.memory();
  final mockApi = MockApiClient();
  final syncWorker = SyncWorker(db: db, apiClient: mockApi);
  
  // Create local product
  final productId = await productRepo.create(...);
  
  // Mock API response
  when(mockApi.createProduct(any))
      .thenAnswer((_) async => {'id': 100});
  
  // Trigger sync
  await syncWorker.triggerSync();
  
  // Verify synced
  final product = await productRepo.getById(productId);
  expect(product.serverId, 100);
  expect(product.syncStatus, SyncStatus.synced);
});
```

### E2E Tests

Test complete offline workflows:

```dart
test('should complete sale while offline', () async {
  // Setup offline mode
  when(mockApi.login(any, any)).thenThrow(NetworkException());
  
  // Login offline
  await authService.login('cashier', 'password');
  
  // Create sale
  final saleId = await saleRepo.createSale(...);
  
  // Verify sale created locally
  final sale = await saleRepo.getById(saleId);
  expect(sale.syncStatus, SyncStatus.pending);
  
  // Verify stock deducted
  final product = await productRepo.getById(productId);
  expect(product.stockQuantity, originalStock - quantitySold);
});
```

## Performance Considerations

### Query Optimization

Use indexes for common queries:
```sql
CREATE INDEX idx_products_active_store 
ON products(is_active, store_id);

CREATE INDEX idx_sales_created_at 
ON sales(created_at DESC);
```

### Batch Operations

Process sync queue in batches:
```dart
final items = await (db.select(db.syncQueue)
  ..where((q) => q.status.equals('pending'))
  ..limit(100))
  .get();
```

### Memory Management

Use streams for live data:
```dart
Stream<List<Product>> watchProducts() {
  return (db.select(db.products)
    ..where((p) => p.isActive.equals(true)))
    .watch();
}
```

## Error Handling

### User-Friendly Messages

```dart
try {
  await productRepo.create(...);
  context.showSuccess('Product created successfully');
} catch (e) {
  context.showError(
    ErrorHandler.getFriendlyMessage(e),
    title: 'Failed to create product',
  );
}
```

### Retry Logic

```dart
Future<void> _retryWithBackoff(SyncQueueData item) async {
  final delay = _calculateBackoff(item.retryCount);
  await Future.delayed(delay);
  
  try {
    await _syncItem(item);
  } catch (e) {
    if (item.retryCount < maxRetries) {
      await _markForRetry(item.id, e.toString());
    } else {
      await _markAsFailed(item.id);
    }
  }
}
```

## Deployment Checklist

- [ ] All tests passing
- [ ] Database indexes created
- [ ] Sync queue processing correctly
- [ ] Conflict resolution working
- [ ] Offline authentication functional
- [ ] Ghost users syncing to server
- [ ] Stock management preventing overselling
- [ ] Error messages user-friendly
- [ ] Background sync configured
- [ ] Performance targets met

## Troubleshooting

### Sync Not Working

1. Check network connectivity
2. Verify API credentials
3. Check sync queue status: `SELECT * FROM sync_queue WHERE status = 'failed'`
4. Review error messages in queue
5. Check WorkManager logs

### Database Issues

1. Check schema version: `PRAGMA user_version`
2. Verify indexes: `SELECT * FROM sqlite_master WHERE type = 'index'`
3. Analyze query plans: `EXPLAIN QUERY PLAN SELECT ...`
4. Check database size: Should be < 100MB for optimal performance

### Conflicts Not Resolving

1. Check conflict records: `SELECT * FROM sync_conflicts`
2. Verify timestamp comparison logic
3. Ensure server `updated_at` is timezone-aware
4. Check conflict resolution UI accessibility

## Resources

- [Drift Documentation](https://drift.simonbinder.eu/)
- [Flutter Offline-First Guide](https://flutter.dev/docs/development/data-and-backend/state-mgmt/options)
- [SQLite Performance Tips](https://www.sqlite.org/optoverview.html)
- [WorkManager Documentation](https://pub.dev/packages/workmanager)

---

**Last Updated:** January 1, 2026  
**Version:** 2.0  
**Author:** Development Team
