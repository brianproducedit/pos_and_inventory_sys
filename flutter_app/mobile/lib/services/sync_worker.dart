import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../db/app_database.dart';
import '../data/remote/api_client.dart';

/// Background sync worker - handles pushing and pulling changes
class SyncWorker {
  final AppDatabase db;
  final ApiClient apiClient;
  final FlutterSecureStorage secureStorage;
  bool _isSyncing = false;

  SyncWorker({
    required this.db,
    required this.apiClient,
    FlutterSecureStorage? storage,
  }) : secureStorage = storage ?? const FlutterSecureStorage();

  /// Trigger a sync operation
  Future<void> triggerSync() async {
    if (_isSyncing) {
      print('SyncWorker: Sync already in progress, skipping');
      return;
    }

    _isSyncing = true;
    print('SyncWorker: Starting sync...');

    try {
      // 1. Push local changes to server
      await _pushChanges();

      // 2. Pull server changes (not yet implemented)
      // await _pullChanges();

      print('SyncWorker: Sync completed successfully');
    } catch (e) {
      print('SyncWorker: Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Push pending local changes to server
  Future<void> _pushChanges() async {
    // Get pending items from sync queue
    final pendingItems = await (db.select(db.syncQueue)
          ..where((q) => q.status.equals('pending'))
          ..orderBy([(q) => OrderingTerm.asc(q.createdAt)])
          ..limit(100))
        .get();

    if (pendingItems.isEmpty) {
      print('SyncWorker: No pending changes to push');
      return;
    }

    print('SyncWorker: Pushing ${pendingItems.length} changes...');

    for (final item in pendingItems) {
      try {
        await _processSyncItem(item);
      } catch (e) {
        print('SyncWorker: Failed to sync item ${item.id}: $e');
        // Update retry count
        await _markSyncItemFailed(item, e.toString());
      }
    }
  }

  /// Process a single sync queue item
  Future<void> _processSyncItem(SyncQueueData item) async {
    // Mark as processing
    await (db.update(db.syncQueue)..where((q) => q.id.equals(item.id)))
        .write(SyncQueueCompanion(
      status: Value('processing'),
      lastAttemptAt: Value(DateTime.now()),
    ));

    final payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;

    switch (item.resourceType) {
      case 'user':
        await _syncUser(item, payload);
        break;
      case 'product':
        await _syncProduct(item, payload);
        break;
      case 'sale':
        await _syncSale(item, payload);
        break;
      case 'store':
        await _syncStore(item, payload);
        break;
      default:
        throw UnsupportedError('Unknown resource type: ${item.resourceType}');
    }

    // Mark as completed and remove from queue
    await (db.delete(db.syncQueue)..where((q) => q.id.equals(item.id))).go();
  }

  /// Sync user changes
  Future<void> _syncUser(
      SyncQueueData item, Map<String, dynamic> payload) async {
    print('SyncWorker: Syncing user: ${item.operation}');

    // Get auth token
    final token = await secureStorage.read(key: 'access_token');
    if (token == null) {
      throw Exception('No auth token available for sync');
    }

    if (item.operation == 'create') {
      // Create user on server
      if (item.clientTempId != null) {
        final localUser = await (db.select(db.users)
              ..where((u) => u.clientId.equals(item.clientTempId!)))
            .getSingleOrNull();

        if (localUser != null) {
          try {
            // Send user data to server
            final serverUser = await apiClient.createUser(
              token: token,
              userData: payload,
            );

            // Update local user with server ID
            await (db.update(db.users)..where((u) => u.id.equals(localUser.id)))
                .write(UsersCompanion(
              serverId: Value(serverUser['id'] as int),
              syncStatus: Value(SyncStatus.synced),
              isLocalOnly: Value(false),
              lastUpdatedAt: Value(DateTime.now()),
            ));

            print(
                'SyncWorker: User created on server, id: ${serverUser['id']}');
          } catch (e) {
            print('SyncWorker: Failed to create user on server: $e');
            rethrow;
          }
        }
      }
    } else if (item.operation == 'update') {
      // Update existing user on server
      final userId = payload['id'] as int?;
      if (userId != null) {
        try {
          // Check if it's a password change
          if (payload['action'] == 'change_password') {
            // Handle password change - remove action field before sending
            final updateData = Map<String, dynamic>.from(payload);
            updateData.remove('action');
            updateData.remove('id');
            updateData.remove('client_id');

            await apiClient.updateUser(
              token: token,
              userId: userId,
              userData: updateData,
            );
          } else {
            // Regular user update
            final updateData = Map<String, dynamic>.from(payload);
            updateData.remove('id');
            updateData.remove('client_id');

            await apiClient.updateUser(
              token: token,
              userId: userId,
              userData: updateData,
            );
          }

          // Update local sync status
          final localUser = await (db.select(db.users)
                ..where((u) => u.serverId.equals(userId)))
              .getSingleOrNull();

          if (localUser != null) {
            await (db.update(db.users)..where((u) => u.id.equals(localUser.id)))
                .write(UsersCompanion(
              syncStatus: Value(SyncStatus.synced),
              lastUpdatedAt: Value(DateTime.now()),
            ));
          }

          print('SyncWorker: User updated on server, id: $userId');
        } catch (e) {
          print('SyncWorker: Failed to update user on server: $e');
          rethrow;
        }
      }
    }
  }

  /// Sync product changes
  Future<void> _syncProduct(
      SyncQueueData item, Map<String, dynamic> payload) async {
    print('SyncWorker: Syncing product: ${item.operation}');

    final token = await secureStorage.read(key: 'access_token');
    if (token == null) {
      throw Exception('No auth token available for sync');
    }

    if (item.operation == 'create') {
      // Create product on server
      if (item.clientTempId != null) {
        final localProduct = await (db.select(db.products)
              ..where((p) => p.clientId.equals(item.clientTempId!)))
            .getSingleOrNull();

        if (localProduct != null) {
          try {
            final serverProduct = await apiClient.createProduct(
              token: token,
              productData: payload,
            );

            await (db.update(db.products)
                  ..where((p) => p.id.equals(localProduct.id)))
                .write(ProductsCompanion(
              serverId: Value(serverProduct['id'] as int),
              syncStatus: Value(SyncStatus.synced),
              lastUpdatedAt: Value(DateTime.now()),
            ));

            print('SyncWorker: Product created on server, id: ${serverProduct['id']}');
          } catch (e) {
            print('SyncWorker: Failed to create product on server: $e');
            rethrow;
          }
        }
      }
    } else if (item.operation == 'update') {
      // Update product on server
      final productId = payload['id'] as int?;
      if (productId != null) {
        try {
          final updateData = Map<String, dynamic>.from(payload);
          updateData.remove('id');
          updateData.remove('client_id');

          await apiClient.updateProduct(
            token: token,
            productId: productId,
            productData: updateData,
          );

          final localProduct = await (db.select(db.products)
                ..where((p) => p.serverId.equals(productId)))
              .getSingleOrNull();

          if (localProduct != null) {
            await (db.update(db.products)
                  ..where((p) => p.id.equals(localProduct.id)))
                .write(ProductsCompanion(
              syncStatus: Value(SyncStatus.synced),
              lastUpdatedAt: Value(DateTime.now()),
            ));
          }

          print('SyncWorker: Product updated on server, id: $productId');
        } catch (e) {
          print('SyncWorker: Failed to update product on server: $e');
          rethrow;
        }
      }
    }
  }

  /// Sync sale changes
  Future<void> _syncSale(
      SyncQueueData item, Map<String, dynamic> payload) async {
    print('SyncWorker: Syncing sale: ${item.operation}');

    final token = await secureStorage.read(key: 'access_token');
    if (token == null) {
      throw Exception('No auth token available for sync');
    }

    if (item.operation == 'create') {
      // Create sale on server
      if (item.clientTempId != null) {
        final localSale = await (db.select(db.sales)
              ..where((s) => s.clientId.equals(item.clientTempId!)))
            .getSingleOrNull();

        if (localSale != null) {
          try {
            final serverSale = await apiClient.createSale(
              token: token,
              saleData: payload,
            );

            // Update sale with server ID
            await (db.update(db.sales)
                  ..where((s) => s.id.equals(localSale.id)))
                .write(SalesCompanion(
              serverId: Value(serverSale['id'] as int),
              syncStatus: Value(SyncStatus.synced),
              lastUpdatedAt: Value(DateTime.now()),
            ));

            // Update sale items sync status
            final saleItems = await (db.select(db.saleItems)
                  ..where((si) => si.saleId.equals(localSale.id)))
                .get();

            for (final saleItem in saleItems) {
              await (db.update(db.saleItems)
                    ..where((si) => si.id.equals(saleItem.id)))
                  .write(SaleItemsCompanion(
                syncStatus: Value(SyncStatus.synced),
              ));
            }

            print('SyncWorker: Sale created on server, id: ${serverSale['id']}');
          } catch (e) {
            print('SyncWorker: Failed to create sale on server: $e');
            rethrow;
          }
        }
      }
    }
  }

  /// Sync store changes
  Future<void> _syncStore(
      SyncQueueData item, Map<String, dynamic> payload) async {
    print('SyncWorker: Syncing store: ${item.operation}');
    // TODO: Implement when Phase 3 is active
  }

  /// Mark sync item as failed
  Future<void> _markSyncItemFailed(SyncQueueData item, String error) async {
    final newRetryCount = item.retryCount + 1;
    final newStatus = newRetryCount >= 5 ? 'failed' : 'pending';

    await (db.update(db.syncQueue)..where((q) => q.id.equals(item.id)))
        .write(SyncQueueCompanion(
      retryCount: Value(newRetryCount),
      lastAttemptAt: Value(DateTime.now()),
      status: Value(newStatus),
      errorMessage: Value(error),
    ));

    if (newStatus == 'failed') {
      print('SyncWorker: Item ${item.id} marked as permanently failed after '
          '${newRetryCount} attempts');
    }
  }

  /// Get sync queue status
  Future<SyncQueueStatus> getQueueStatus() async {
    final pending = await (db.select(db.syncQueue)
          ..where((q) => q.status.equals('pending')))
        .get();

    final processing = await (db.select(db.syncQueue)
          ..where((q) => q.status.equals('processing')))
        .get();

    final failed = await (db.select(db.syncQueue)
          ..where((q) => q.status.equals('failed')))
        .get();

    return SyncQueueStatus(
      pendingCount: pending.length,
      processingCount: processing.length,
      failedCount: failed.length,
    );
  }

  /// Get last sync timestamp
  Future<DateTime?> getLastSyncTime() async {
    final lastItem = await (db.select(db.syncQueue)
          ..orderBy([(q) => OrderingTerm.desc(q.lastAttemptAt)])
          ..limit(1))
        .getSingleOrNull();

    return lastItem?.lastAttemptAt;
  }
}

/// Sync queue status information
class SyncQueueStatus {
  final int pendingCount;
  final int processingCount;
  final int failedCount;

  SyncQueueStatus({
    required this.pendingCount,
    required this.processingCount,
    required this.failedCount,
  });

  bool get hasPending => pendingCount > 0;
  bool get hasFailures => failedCount > 0;
  bool get isSyncing => processingCount > 0;
  int get totalUnsynced => pendingCount + failedCount;
}
