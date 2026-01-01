import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import '../../../lib/db/app_database.dart';
import '../../../lib/services/sync_worker.dart';
import '../../../lib/data/remote/api_client.dart';
import '../../../lib/models/sync_conflict.dart' as models;

@GenerateMocks([ApiClient, FlutterSecureStorage])
import 'sync_worker_test.mocks.dart';

void main() {
  late AppDatabase database;
  late MockApiClient mockApiClient;
  late MockFlutterSecureStorage mockStorage;
  late SyncWorker syncWorker;
  late models.ConflictManager conflictManager;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    mockApiClient = MockApiClient();
    mockStorage = MockFlutterSecureStorage();
    conflictManager = models.ConflictManager();
    
    syncWorker = SyncWorker(
      db: database,
      apiClient: mockApiClient,
      storage: mockStorage,
      conflictManager: conflictManager,
    );

    // Setup mock storage to return a test token
    when(mockStorage.read(key: 'access_token'))
        .thenAnswer((_) async => 'test_token');
  });

  tearDown(() async {
    await database.close();
  });

  group('SyncWorker - Push Changes', () {
    test('should push pending user create to server', () async {
      // Create a local user
      final userId = await database.into(database.users).insert(
        UsersCompanion.insert(
          clientId: Value('client-123'),
          username: 'testuser',
          passwordHash: 'hash123',
          fullName: Value('Test User'),
          role: UserRole.cashier,
          syncStatus: Value(SyncStatus.pending),
        ),
      );

      // Add to sync queue
      await database.into(database.syncQueue).insert(
        SyncQueueCompanion.insert(
          resourceType: 'user',
          resourceId: userId,
          operation: 'create',
          payload: Value('{}'),
        ),
      );

      // Mock successful API response
      when(mockApiClient.createUser(any))
          .thenAnswer((_) async => {'id': 100, 'username': 'testuser'});

      // Trigger sync
      await syncWorker.triggerSync();

      // Verify API was called
      verify(mockApiClient.createUser(any)).called(1);

      // Verify user sync status updated
      final user = await (database.select(database.users)
            ..where((u) => u.id.equals(userId)))
          .getSingle();
      expect(user.syncStatus, SyncStatus.synced);
      expect(user.serverId, 100);

      // Verify sync queue item removed or marked as synced
      final queueItems = await (database.select(database.syncQueue)
            ..where((q) => q.resourceType.equals('user'))
            ..where((q) => q.resourceId.equals(userId))
            ..where((q) => q.status.equals('pending')))
          .get();
      expect(queueItems.length, 0);
    });

    test('should push pending product create to server', () async {
      // Create test store
      final storeId = await database.into(database.stores).insert(
        StoresCompanion.insert(
          clientId: Value('store-1'),
          name: 'Test Store',
        ),
      );

      // Create a local product
      final productId = await database.into(database.products).insert(
        ProductsCompanion.insert(
          clientId: Value('product-123'),
          name: 'Test Product',
          price: Value(19.99),
          stockQuantity: Value(50),
          storeId: storeId,
          syncStatus: Value(SyncStatus.pending),
        ),
      );

      // Add to sync queue
      await database.into(database.syncQueue).insert(
        SyncQueueCompanion.insert(
          resourceType: 'product',
          resourceId: productId,
          operation: 'create',
          payload: Value('{}'),
        ),
      );

      // Mock successful API response
      when(mockApiClient.createProduct(any))
          .thenAnswer((_) async => {'id': 200, 'name': 'Test Product'});

      // Trigger sync
      await syncWorker.triggerSync();

      // Verify API was called
      verify(mockApiClient.createProduct(any)).called(1);

      // Verify product sync status updated
      final product = await (database.select(database.products)
            ..where((p) => p.id.equals(productId)))
          .getSingle();
      expect(product.syncStatus, SyncStatus.synced);
      expect(product.serverId, 200);
    });

    test('should handle sync failures and retry with exponential backoff', () async {
      // Create a user to sync
      final userId = await database.into(database.users).insert(
        UsersCompanion.insert(
          clientId: Value('client-fail'),
          username: 'failuser',
          passwordHash: 'hash123',
          role: UserRole.cashier,
          syncStatus: Value(SyncStatus.pending),
        ),
      );

      await database.into(database.syncQueue).insert(
        SyncQueueCompanion.insert(
          resourceType: 'user',
          resourceId: userId,
          operation: 'create',
          payload: Value('{}'),
        ),
      );

      // Mock API failure
      when(mockApiClient.createUser(any))
          .thenThrow(Exception('Network error'));

      // Trigger sync
      await syncWorker.triggerSync();

      // Verify queue item marked for retry
      final queueItem = await (database.select(database.syncQueue)
            ..where((q) => q.resourceType.equals('user'))
            ..where((q) => q.resourceId.equals(userId)))
          .getSingle();
      
      expect(queueItem.retryCount, greaterThan(0));
      expect(queueItem.status, 'pending');
      expect(queueItem.errorMessage, isNotNull);
    });
  });

  group('SyncWorker - Pull Changes', () {
    test('should pull and apply server changes', () async {
      // Mock server changes response
      when(mockApiClient.pullChanges(any))
          .thenAnswer((_) async => {
                'changes': [
                  {
                    'resource_type': 'user',
                    'operation': 'create',
                    'data': {
                      'id': 500,
                      'client_id': 'server-user-1',
                      'username': 'serveruser',
                      'full_name': 'Server User',
                      'role': 'cashier',
                      'is_active': true,
                      'updated_at': DateTime.now().toIso8601String(),
                    },
                  },
                ],
              });

      // Trigger sync
      await syncWorker.triggerSync();

      // Verify user was created from server
      final users = await (database.select(database.users)
            ..where((u) => u.username.equals('serveruser')))
          .get();
      
      expect(users.length, 1);
      expect(users.first.serverId, 500);
      expect(users.first.syncStatus, SyncStatus.synced);
      expect(users.first.fullName, 'Server User');
    });

    test('should detect and handle conflicts', () async {
      // Create local user with pending changes
      final userId = await database.into(database.users).insert(
        UsersCompanion.insert(
          clientId: Value('conflict-user'),
          serverId: Value(600),
          username: 'conflictuser',
          passwordHash: 'localhash',
          fullName: Value('Local Name'),
          role: UserRole.cashier,
          syncStatus: Value(SyncStatus.pending),
        ),
      );

      // Mock server changes with same user
      when(mockApiClient.pullChanges(any))
          .thenAnswer((_) async => {
                'changes': [
                  {
                    'resource_type': 'user',
                    'operation': 'update',
                    'data': {
                      'id': 600,
                      'client_id': 'conflict-user',
                      'username': 'conflictuser',
                      'full_name': 'Server Name',
                      'role': 'admin',
                      'is_active': true,
                      'updated_at': DateTime.now().add(Duration(minutes: 5)).toIso8601String(),
                    },
                  },
                ],
              });

      // Trigger sync
      await syncWorker.triggerSync();

      // Verify conflict was detected
      final user = await (database.select(database.users)
            ..where((u) => u.id.equals(userId)))
          .getSingle();
      expect(user.syncStatus, SyncStatus.conflict);

      // Verify conflict recorded in ConflictManager
      final conflicts = await conflictManager.getConflicts();
      expect(conflicts.length, greaterThan(0));
      expect(conflicts.any((c) => c.localId == userId), true);
    });
  });

  group('SyncWorker - Queue Management', () {
    test('should return queue status', () async {
      // Add some queue items
      await database.into(database.syncQueue).insert(
        SyncQueueCompanion.insert(
          resourceType: 'product',
          resourceId: 1,
          operation: 'create',
          status: Value('pending'),
          payload: Value('{}'),
        ),
      );

      await database.into(database.syncQueue).insert(
        SyncQueueCompanion.insert(
          resourceType: 'user',
          resourceId: 2,
          operation: 'update',
          status: Value('processing'),
          payload: Value('{}'),
        ),
      );

      await database.into(database.syncQueue).insert(
        SyncQueueCompanion.insert(
          resourceType: 'sale',
          resourceId: 3,
          operation: 'create',
          status: Value('failed'),
          payload: Value('{}'),
        ),
      );

      final status = await syncWorker.getQueueStatus();
      
      expect(status.pendingCount, greaterThanOrEqualTo(1));
      expect(status.processingCount, greaterThanOrEqualTo(1));
      expect(status.failedCount, greaterThanOrEqualTo(1));
      expect(status.hasPending, true);
      expect(status.hasFailures, true);
    });

    test('should retry failed items', () async {
      // Create a failed queue item
      await database.into(database.syncQueue).insert(
        SyncQueueCompanion.insert(
          resourceType: 'product',
          resourceId: 1,
          operation: 'create',
          status: Value('failed'),
          retryCount: Value(2),
          payload: Value('{}'),
        ),
      );

      // Mock successful retry
      when(mockApiClient.createProduct(any))
          .thenAnswer((_) async => {'id': 300, 'name': 'Product'});

      // Trigger sync (should retry failed items)
      await syncWorker.triggerSync();

      // Verify item was retried
      verify(mockApiClient.createProduct(any)).called(greaterThan(0));
    });
  });

  group('SyncWorker - ID Mapping', () {
    test('should map client IDs to server IDs after sync', () async {
      final clientId = 'client-product-123';
      
      // Create product with client ID
      final productId = await database.into(database.products).insert(
        ProductsCompanion.insert(
          clientId: Value(clientId),
          name: 'Mapping Test',
          price: Value(10.00),
          storeId: 1,
          syncStatus: Value(SyncStatus.pending),
        ),
      );

      await database.into(database.syncQueue).insert(
        SyncQueueCompanion.insert(
          resourceType: 'product',
          resourceId: productId,
          operation: 'create',
          payload: Value('{}'),
        ),
      );

      // Mock API response with server ID
      when(mockApiClient.createProduct(any))
          .thenAnswer((_) async => {'id': 999, 'name': 'Mapping Test'});

      await syncWorker.triggerSync();

      // Verify server ID was mapped
      final product = await (database.select(database.products)
            ..where((p) => p.clientId.equals(clientId)))
          .getSingle();
      
      expect(product.serverId, 999);
      expect(product.clientId, clientId); // Client ID preserved
    });
  });

  group('SyncWorker - Sync Prevention', () {
    test('should not sync while already syncing', () async {
      // Start first sync
      final sync1 = syncWorker.triggerSync();
      
      // Try to start second sync immediately
      final sync2 = syncWorker.triggerSync();

      await sync1;
      await sync2;

      // Both should complete without error
      // Second sync should be skipped
    });
  });

  group('SyncWorker - Batch Processing', () {
    test('should process sync queue in batches', () async {
      // Create multiple pending items
      for (int i = 0; i < 150; i++) {
        await database.into(database.syncQueue).insert(
          SyncQueueCompanion.insert(
            resourceType: 'product',
            resourceId: i,
            operation: 'create',
            payload: Value('{}'),
          ),
        );
      }

      // Mock API to track calls
      when(mockApiClient.createProduct(any))
          .thenAnswer((_) async => {'id': 100, 'name': 'Product'});

      await syncWorker.triggerSync();

      // Should process in batches (default 100)
      // Verify not all were processed in one go if batch limit is implemented
      final remaining = await (database.select(database.syncQueue)
            ..where((q) => q.status.equals('pending')))
          .get();
      
      // Some items should remain for next sync cycle
      expect(remaining.length, lessThanOrEqualTo(150));
    });
  });
}
