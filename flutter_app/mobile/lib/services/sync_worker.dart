import 'dart:convert';
import 'package:drift/drift.dart';
import '../db/app_database.dart';
import '../data/remote/api_client.dart';

/// Background sync worker - handles pushing and pulling changes
class SyncWorker {
  final AppDatabase db;
  final ApiClient apiClient;
  bool _isSyncing = false;

  SyncWorker({
    required this.db,
    required this.apiClient,
  });

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
          ..orderBy([
            (q) => OrderingTerm.asc(q.createdAt)
          ])
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
        throw UnsupportedError(
            'Unknown resource type: ${item.resourceType}');
    }

    // Mark as completed and remove from queue
    await (db.delete(db.syncQueue)..where((q) => q.id.equals(item.id))).go();
  }

  /// Sync user changes
  Future<void> _syncUser(
      SyncQueueData item, Map<String, dynamic> payload) async {
    // For now, just a placeholder - will implement when backend endpoints are ready
    print('SyncWorker: Syncing user: ${item.operation}');

    // Simulate successful sync
    if (item.operation == 'create') {
      // When user is created on server, we'd get back server_id
      // Update local user record with server_id
      if (item.clientTempId != null) {
        final localUser = await (db.select(db.users)
              ..where((u) => u.clientId.equals(item.clientTempId!)))
            .getSingleOrNull();

        if (localUser != null) {
          // For now, simulate server ID assignment
          final mockServerId = DateTime.now().millisecondsSinceEpoch % 100000;

          await (db.update(db.users)..where((u) => u.id.equals(localUser.id)))
              .write(UsersCompanion(
            serverId: Value(mockServerId),
            syncStatus: Value(SyncStatus.synced),
            isLocalOnly: Value(false),
          ));

          print('SyncWorker: User synced, assigned server_id: $mockServerId');
        }
      }
    } else if (item.operation == 'update') {
      // Update existing user on server
      print('SyncWorker: User update synced');
    }
  }

  /// Sync product changes
  Future<void> _syncProduct(
      SyncQueueData item, Map<String, dynamic> payload) async {
    print('SyncWorker: Syncing product: ${item.operation}');
    // TODO: Implement when Phase 3 is active
  }

  /// Sync sale changes
  Future<void> _syncSale(
      SyncQueueData item, Map<String, dynamic> payload) async {
    print('SyncWorker: Syncing sale: ${item.operation}');
    // TODO: Implement when Phase 4 is active
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
          ..orderBy([
            (q) => OrderingTerm.desc(q.lastAttemptAt)
          ])
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
