# Developer Guide: Offline-First Development

## Overview

This guide provides comprehensive documentation for developers working on the POS & Inventory system's offline-first architecture. The system implements a robust sync mechanism that allows seamless operation in offline environments while maintaining data consistency across devices.

## Architecture Overview

### Core Components

#### 1. Sync Service (`sync_service.dart`)
**Location:** `lib/sync/sync_service.dart`

**Purpose:** Central coordinator for all sync operations

**Key Methods:**
```dart
// Create operations
Future<String> enqueueCreateProduct({...})

// Update operations
Future<void> enqueueUpdateProduct({...})

// Delete operations
Future<void> enqueueDeleteProduct({...})

// Sync operations
Future<Map<String, dynamic>> pushChanges()
Future<List<Map<String, dynamic>>> pullChanges()
```

**Usage:**
```dart
final syncService = SyncService(database, serverBase: 'https://api.example.com');

// Create a product (queues for sync)
final clientId = await syncService.enqueueCreateProduct(
  name: 'New Product',
  price: 29.99,
  stock: 100,
  storeId: 1
);

// Push changes to server
final result = await syncService.pushChanges(jwtToken: token);
```

#### 2. App Database (`app_database.dart`)
**Location:** `lib/db/app_database.dart`

**Purpose:** Local SQLite database with Drift ORM

**Key Tables:**
- `Products`: Product catalog with offline support
- `SyncQueue`: Pending changes queue
- `Changes`: Server change log for efficient sync

**Features:**
- In-memory database for testing
- Automatic schema migrations
- Conflict resolution support

#### 3. Sync Provider (`sync_provider.dart`)
**Location:** `lib/providers/sync_provider.dart`

**Purpose:** State management for sync operations

**Key Features:**
- Sync status monitoring
- Conflict resolution UI
- Offline queue management
- Network status detection

## Development Workflow

### 1. Setting Up Development Environment

#### Database Setup
```bash
# Generate database code
flutter pub run build_runner build --delete-conflicting-outputs

# Run migrations (if needed)
# The app handles schema creation automatically
```

#### Feature Flags
Configure feature flags in your environment:
```dart
// Check if sync is enabled
if (isFeatureEnabled('SYNC_ENABLED')) {
  // Perform sync operation
}
```

### 2. Implementing New Syncable Entities

#### Step 1: Define Database Schema
```dart
class YourEntity extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientId => text().nullable()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
```

#### Step 2: Add to Database Class
```dart
@DriftDatabase(tables: [Products, YourEntity, SyncQueue])
class AppDatabase extends _$AppDatabase {
  // Add CRUD methods
  Future<List<YourEntityData>> getAllYourEntities() => select(yourEntity).get();
  Future<int> insertYourEntity(YourEntityCompanion entity) => into(yourEntity).insert(entity);
}
```

#### Step 3: Extend Sync Service
```dart
class SyncService {
  // Add entity-specific methods
  Future<String> enqueueCreateYourEntity({...}) async {
    final clientId = _uuid.v4();
    // Create local record
    await db.insertYourEntity(YourEntityCompanion(
      clientId: Value(clientId),
      name: name,
      // ... other fields
    ));

    // Queue for server sync
    final payload = {
      'resource_type': 'your_entity',
      'operation': 'create',
      'temp_id': clientId,
      'data': {/* entity data */}
    };

    await db.enqueueChange(
      clientTempId: clientId,
      resourceType: 'your_entity',
      operation: 'create',
      payloadJson: jsonEncode(payload)
    );

    return clientId;
  }
}
```

#### Step 4: Update Sync Router (Backend)
```python
@router.post("/api/sync/push")
def push_changes(payload: SyncPushRequest, db: Session = Depends(get_db)):
    for ch in payload.changes:
        if ch.resource_type == 'your_entity':
            if ch.operation == 'create':
                # Handle creation
                entity = YourEntity(name=ch.data['name'], ...)
                db.add(entity)
                db.commit()
                # Record change for other clients
                _make_change(db, entity_type='your_entity', entity_id=str(entity.id), ...)
```

### 3. Conflict Resolution

#### Types of Conflicts
1. **Server Wins**: Discard local changes
2. **Client Wins**: Overwrite server data
3. **Manual Resolution**: Present to user
4. **Merge**: Combine changes intelligently

#### Implementing Conflict Resolution
```dart
class ConflictResolver {
  Future<ConflictResolution> resolve(Product local, Product server) async {
    // Compare timestamps
    if (local.updatedAt.isAfter(server.updatedAt)) {
      return ConflictResolution.clientWins;
    }

    // Check if changes are compatible
    if (local.price != server.price && local.name == server.name) {
      // Price conflict - manual resolution needed
      return ConflictResolution.manual;
    }

    return ConflictResolution.serverWins;
  }
}
```

### 4. Testing Offline Functionality

#### Unit Tests
```dart
void main() {
  group('Sync Service Tests', () {
    test('creates product offline', () async {
      final db = AppDatabase.inMemory();
      final sync = SyncService(db);

      final clientId = await sync.enqueueCreateProduct(
        name: 'Test Product',
        price: 10.0,
        stock: 50,
        storeId: 1
      );

      final products = await db.getAllProducts();
      expect(products.length, equals(1));
      expect(products[0].clientId, equals(clientId));
    });
  });
}
```

#### Integration Tests
```dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline to online sync', (tester) async {
    // Setup mock server
    final mockServer = MockSyncServer();
    await mockServer.start();

    // Test offline operations
    // Test sync when online
    // Verify data consistency
  });
}
```

## Best Practices

### 1. Data Modeling
- Always include `clientId` for tracking
- Use `serverId` for server references
- Include timestamps for conflict resolution
- Design for eventual consistency

### 2. Error Handling
```dart
try {
  await syncService.pushChanges();
} on NetworkException catch (e) {
  // Handle network issues
  await showOfflineMessage();
} on ConflictException catch (e) {
  // Handle conflicts
  await showConflictResolutionDialog(e.conflicts);
} catch (e) {
  // Handle other errors
  await logError(e);
}
```

### 3. Performance Optimization
- Batch sync operations
- Implement pagination for large datasets
- Use compression for payloads
- Cache frequently accessed data

### 4. Security Considerations
- Encrypt sensitive data locally
- Validate server certificates
- Implement proper authentication
- Use secure token storage

## Troubleshooting

### Common Issues

#### Sync Queue Growing
**Symptoms:** Pending changes accumulating
**Solution:**
```dart
// Check server connectivity
final isOnline = await connectivity.checkConnectivity();

// Clear old failed attempts
await db.clearOldSyncAttempts();

// Manual sync trigger
await syncService.forceSync();
```

#### Data Inconsistencies
**Symptoms:** Different data on different devices
**Solution:**
```dart
// Full data refresh
await syncService.requestFullSync();

// Check conflict logs
final conflicts = await db.getRecentConflicts();
```

#### Performance Issues
**Symptoms:** Slow sync operations
**Solution:**
```dart
// Enable bulk operations
if (isFeatureEnabled('BULK_SYNC_ENABLED')) {
  await syncService.bulkSync();
}

// Optimize batch size
await syncService.setBatchSize(50);
```

## API Reference

### Sync Service Methods

#### enqueueCreateProduct
```dart
Future<String> enqueueCreateProduct({
  required String name,
  double price = 0.0,
  int stock = 0,
  int? storeId
})
```
Creates a product locally and queues it for server sync.

#### pushChanges
```dart
Future<Map<String, dynamic>> pushChanges({String? jwtToken})
```
Sends local changes to the server and handles responses.

#### pullChanges
```dart
Future<List<Map<String, dynamic>>> pullChanges({int? sinceSeq})
```
Retrieves changes from the server since the last sync.

### Database Methods

#### getAllProducts
```dart
Future<List<Product>> getAllProducts()
```
Retrieves all products from local database.

#### enqueueChange
```dart
Future<int> enqueueChange({
  String? clientTempId,
  required String resourceType,
  required String operation,
  required String payloadJson
})
```
Queues a change for server synchronization.

## Migration Guide

### Upgrading from Non-Sync to Sync
1. Add sync fields to existing models
2. Implement change tracking
3. Add conflict resolution
4. Update UI for offline indicators
5. Test offline scenarios thoroughly

### Version Compatibility
- **v1.0**: Basic sync functionality
- **v1.1**: Conflict resolution
- **v1.2**: Bulk operations
- **v2.0**: Real-time sync (planned)

## Support and Resources

- **API Documentation**: `/docs` endpoint
- **Health Dashboard**: `scripts/sync_health_dashboard.py`
- **Test Coverage**: Run `flutter test` for full suite
- **Logs**: Check device logs for sync operations

---

*Last updated: 2025-12-30*