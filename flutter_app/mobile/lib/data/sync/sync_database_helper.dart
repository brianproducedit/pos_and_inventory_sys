import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// NOTE: sqflite is intentionally used here for sync operations that require
// raw transaction access with nested queries. The postgres_sync_service.dart
// needs this for complex batch sync operations. All other app code uses Drift.
import 'package:sqflite/sqflite.dart' as sqflite;
import '../../db/app_database.dart';

/// Unified sync database helper that works directly with Drift's AppDatabase.
/// Replaces legacy DatabaseHelper for all sync operations.
///
/// This class provides:
/// - Sync queue operations (pending items, marking synced, retries)
/// - Sync metadata (server_seq, client_seq tracking)
/// - Sync error logging
/// - Raw database access for legacy sync service compatibility
///
/// IMPORTANT: Both Drift and raw sqflite access the same database file (app.sqlite).
/// The database is configured with WAL mode and busy_timeout to prevent locks.
/// All sync operations must acquire the sync lock before database operations.
class SyncDatabaseHelper {
  final AppDatabase _db;
  static sqflite.Database? _rawDb;

  SyncDatabaseHelper(this._db);

  /// Execute database operations with automatic retry on database_closed errors
  Future<R> _withDatabaseRetry<R>(Future<R> Function() operation) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        return await operation();
      } on DriftWrappedException catch (e) {
        if (e.toString().contains('database_closed') &&
            retryCount < maxRetries - 1) {
          retryCount++;
          debugPrint(
              '🔁 SyncDatabaseHelper: Database closed error (attempt $retryCount/$maxRetries), retrying...');
          // Wait a bit before retrying
          await Future.delayed(Duration(milliseconds: 100 * retryCount));
          // Force database reconnection by closing and reopening
          try {
            await _db.close();
            // The database will be reopened on next access
          } catch (closeError) {
            debugPrint(
                '⚠️ SyncDatabaseHelper: Error closing DB during retry: $closeError');
          }
          continue;
        }
        rethrow;
      } catch (e) {
        // For non-database errors, don't retry
        rethrow;
      }
    }

    throw Exception(
        'Failed to execute database operation after $maxRetries attempts');
  }

  /// Get the Drift database for direct access
  AppDatabase get driftDatabase => _db;

  /// Get raw sqflite database for legacy sync operations.
  /// This opens the same database file that Drift uses.
  /// CRITICAL: This connection is configured with WAL mode and busy_timeout
  /// to match the Drift connection and prevent database locks.
  Future<sqflite.Database> get database async {
    // If the cached connection is open, return it
    if (_rawDb != null && _rawDb!.isOpen) return _rawDb!;

    final dbFolder = await getApplicationDocumentsDirectory();
    final path = p.join(dbFolder.path, 'app.sqlite');

    // If we have a cached but closed connection, drop it and reopen
    if (_rawDb != null && !_rawDb!.isOpen) {
      debugPrint('🔁 Raw sqflite DB was closed; reopening');
      try {
        await _rawDb!.close();
      } catch (_) {}
      _rawDb = null;
    }

    // Attempt to open the raw sqflite database. If opening fails with a
    // database_closed error, try once more after clearing the cached handle.
    try {
      _rawDb = await sqflite.openDatabase(
        path,
        onConfigure: (db) async {
          // Enable WAL mode for concurrent read/write support
          // Use rawQuery for journal_mode since it returns a result row on Android
          await db.rawQuery('PRAGMA journal_mode=WAL');
          // Set busy timeout to 30 seconds to match Drift connection
          await db.rawQuery('PRAGMA busy_timeout=30000');
          // Enable foreign keys
          await db.rawQuery('PRAGMA foreign_keys = ON');
          // Set synchronous mode to NORMAL (safe with WAL)
          await db.rawQuery('PRAGMA synchronous=NORMAL');
          debugPrint(
              '✅ Raw sqflite database configured (WAL mode, 30s busy timeout)');
        },
        // Use single instance mode to avoid multiple connections
        singleInstance: true,
      );
    } on sqflite.DatabaseException catch (e) {
      debugPrint('⚠️ Failed to open raw DB: $e');
      // Try to recover from a 'database_closed' error by clearing state and retrying once
      if (e.toString().contains('database_closed')) {
        debugPrint('🔁 Attempting to reopen raw DB after database_closed');
        _rawDb = null;
        try {
          _rawDb = await sqflite.openDatabase(
            path,
            onConfigure: (db) async {
              await db.rawQuery('PRAGMA journal_mode=WAL');
              await db.rawQuery('PRAGMA busy_timeout=30000');
              await db.rawQuery('PRAGMA foreign_keys = ON');
              await db.rawQuery('PRAGMA synchronous=NORMAL');
            },
            singleInstance: true,
          );
        } catch (e2) {
          debugPrint('❌ Reopen attempt failed: $e2');
          rethrow; // Let caller handle the failure
        }
      } else {
        rethrow; // Unknown sqflite error - bubble up
      }
    }

    if (_rawDb == null) {
      throw Exception('Could not open raw sqflite database at $path');
    }

    return _rawDb!;
  }

  /// Close the raw database connection if open.
  /// Call this when the app is closing or when you need to reset the database.
  Future<void> closeRawDatabase() async {
    if (_rawDb != null && _rawDb!.isOpen) {
      try {
        await _rawDb!.close();
      } catch (e) {
        debugPrint('⚠️ Error closing raw DB: $e');
      }
      _rawDb = null;
      debugPrint('🔒 Raw sqflite database connection closed');
    }
  }

  /// Run a callback with a raw sqflite database, retrying once on a
  /// `database_closed` error.
  Future<T> withRawDb<T>(Future<T> Function(sqflite.Database db) fn) async {
    try {
      final db = await database;
      return await fn(db);
    } on sqflite.DatabaseException catch (e) {
      // If the DB was closed unexpectedly, try to recover by reopening once
      if (e.toString().contains('database_closed')) {
        debugPrint('🔁 Detected database_closed - attempting recovery');
        await closeRawDatabase();
        final db = await database; // may rethrow if reopen fails
        return await fn(db);
      }
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC QUEUE OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get pending sync items in the queue, ordered by id (oldest first)
  Future<List<Map<String, dynamic>>> getPendingSyncItems({int? limit}) async {
    return await _withDatabaseRetry(() async {
      final query = _db.select(_db.syncQueue)
        ..where((q) => q.status.equals('pending'))
        ..orderBy([(q) => OrderingTerm.asc(q.id)]);

      if (limit != null) {
        query.limit(limit);
      }

      final items = await query.get();

      // Map Drift schema to sync service expected format
      return items.map((item) {
        // resource_type is singular (product, store, user)
        // table_name needs to be plural (products, stores, users)
        final resourceType = item.resourceType;
        String tableName = resourceType;
        if (!tableName.endsWith('s') && resourceType != 'analytics_event') {
          tableName = '${tableName}s';
        }
        if (resourceType == 'analytics_event') {
          tableName = 'analytics_events';
        }

        // Parse entity_id to get the actual row ID of the entity
        // CRITICAL: row_id must be the local database ID of the entity (user, store, product)
        // NOT the sync queue item ID!
        final rowId =
            item.entityId != null ? int.tryParse(item.entityId!) : null;

        return {
          'id': item.id, // Sync queue item ID
          'table_name': tableName,
          'row_id': rowId ??
              item.id, // Entity's local DB ID (fallback to queue ID if not set)
          'action': item.operation.toUpperCase(),
          'payload': item.payloadJson,
          'payload_json': item.payloadJson,
          'client_seq': item.clientSeq,
          'status': item.status,
          'retry_count': item.retryCount,
          'created_at': item.createdAt.millisecondsSinceEpoch,
          'client_temp_id': item.clientTempId,
          'entity_id': item.entityId,
        };
      }).toList();
    });
  }

  /// Mark a sync queue item as synced
  Future<void> markSyncItemAsSynced(int queueId) async {
    return await _withDatabaseRetry(() async {
      await (_db.update(_db.syncQueue)..where((q) => q.id.equals(queueId)))
          .write(const SyncQueueCompanion(status: Value('synced')));
    });
  }

  /// Increment retry count for a failed sync item
  Future<void> incrementRetry(int queueId) async {
    return await _withDatabaseRetry(() async {
      final item = await (_db.select(_db.syncQueue)
            ..where((q) => q.id.equals(queueId)))
          .getSingleOrNull();

      if (item != null) {
        final newRetryCount = item.retryCount + 1;
        final newStatus = newRetryCount >= 5 ? 'failed' : item.status;

        await (_db.update(_db.syncQueue)..where((q) => q.id.equals(queueId)))
            .write(SyncQueueCompanion(
          retryCount: Value(newRetryCount),
          lastAttemptAt: Value(DateTime.now()),
          status: Value(newStatus),
        ));
      }
    });
  }

  /// Re-enqueue a failed item for retry
  Future<void> reenqueueQueueItem(int queueId) async {
    return await _withDatabaseRetry(() async {
      await (_db.update(_db.syncQueue)..where((q) => q.id.equals(queueId)))
          .write(const SyncQueueCompanion(
        retryCount: Value(0),
        status: Value('pending'),
        errorMessage: Value(null),
      ));
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC METADATA (SERVER SEQ / CLIENT SEQ)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get the last server sequence number received
  Future<int> getLastServerSeq() async {
    return await _withDatabaseRetry(() async {
      final row = await (_db.select(_db.syncMeta)
            ..where((m) => m.key.equals('last_server_seq')))
          .getSingleOrNull();

      if (row == null) return 0;
      return int.tryParse(row.value ?? '') ?? 0;
    });
  }

  /// Set the last server sequence number
  Future<void> setLastServerSeq(int seq) async {
    return await _withDatabaseRetry(() async {
      await _db.into(_db.syncMeta).insertOnConflictUpdate(
            SyncMetaCompanion.insert(
              key: 'last_server_seq',
              value: Value(seq.toString()),
            ),
          );
    });
  }

  /// Get the last pushed client sequence number
  Future<int> getLastPushedClientSeq() async {
    return await _withDatabaseRetry(() async {
      final row = await (_db.select(_db.syncMeta)
            ..where((m) => m.key.equals('last_pushed_client_seq')))
          .getSingleOrNull();

      if (row == null) return 0;
      return int.tryParse(row.value ?? '') ?? 0;
    });
  }

  /// Set the last pushed client sequence
  Future<void> setLastPushedClientSeq(int seq) async {
    return await _withDatabaseRetry(() async {
      await _db.into(_db.syncMeta).insertOnConflictUpdate(
            SyncMetaCompanion.insert(
              key: 'last_pushed_client_seq',
              value: Value(seq.toString()),
            ),
          );
    });
  }

  /// Get next client sequence (within a transaction)
  Future<int> getNextClientSeqWithTxn(dynamic txn) async {
    return await _withDatabaseRetry(() async {
      // For now, just use the main db - transactions are handled by caller
      final row = await (_db.select(_db.syncMeta)
            ..where((m) => m.key.equals('last_client_seq')))
          .getSingleOrNull();

      int lastSeq = 0;
      if (row != null) {
        lastSeq = int.tryParse(row.value ?? '') ?? 0;
      }

      final nextSeq = lastSeq + 1;
      await _db.into(_db.syncMeta).insertOnConflictUpdate(
            SyncMetaCompanion.insert(
              key: 'last_client_seq',
              value: Value(nextSeq.toString()),
            ),
          );

      return nextSeq;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC ERROR LOGGING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Log a sync error
  Future<void> logSyncError({
    required int queueId,
    required String tableName,
    required int rowId,
    required String error,
  }) async {
    return await _withDatabaseRetry(() async {
      debugPrint(
          '📛 Sync error for queue $queueId ($tableName/$rowId): $error');

      // Store error in the queue item's error_message field
      await (_db.update(_db.syncQueue)..where((q) => q.id.equals(queueId)))
          .write(SyncQueueCompanion(errorMessage: Value(error)));
    });
  }

  /// Get sync errors (items with error_message set)
  Future<List<Map<String, dynamic>>> getSyncErrors({int limit = 100}) async {
    return await _withDatabaseRetry(() async {
      final query = _db.select(_db.syncQueue)
        ..where((q) => q.errorMessage.isNotNull())
        ..orderBy([(q) => OrderingTerm.desc(q.id)])
        ..limit(limit);

      final items = await query.get();
      return items.map((item) {
        // Map resource_type to table_name (plural form)
        final resourceType = item.resourceType;
        String tableName = resourceType;
        if (!tableName.endsWith('s') && resourceType != 'analytics_event') {
          tableName = '${tableName}s';
        }

        return {
          'id': item.id,
          'queue_id': item.id,
          'table_name': tableName,
          'row_id': item.id,
          'error': item.errorMessage ?? '',
          'created_at': item.createdAt.millisecondsSinceEpoch,
          'resource_type': item.resourceType,
          'operation': item.operation,
        };
      }).toList();
    });
  }

  /// Clear error for a queue item
  Future<void> clearSyncError(int queueId) async {
    return await _withDatabaseRetry(() async {
      await (_db.update(_db.syncQueue)..where((q) => q.id.equals(queueId)))
          .write(const SyncQueueCompanion(errorMessage: Value(null)));
    });
  }

  /// Clear all errors for queue items
  Future<void> clearErrorsForQueue(int queueId) async {
    await clearSyncError(queueId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEANUP OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Clean up orphaned products (no server_id, older than threshold)
  Future<int> cleanupOrphanedProducts({int maxAgeMs = 86400000}) async {
    return await _withDatabaseRetry(() async {
      final cutoffTime =
          DateTime.now().subtract(Duration(milliseconds: maxAgeMs));

      final deleted = await (_db.delete(_db.products)
            ..where((p) =>
                p.serverId.isNull() &
                p.lastUpdatedAt.isSmallerThanValue(cutoffTime)))
          .go();

      debugPrint('🧹 Cleaned up $deleted orphaned products');
      return deleted;
    });
  }

  /// Remove duplicate products by SKU and store_id, keeping the one with server_id or oldest
  Future<int> cleanupDuplicateProducts() async {
    return await _withDatabaseRetry(() async {
      debugPrint('🧹 Starting Drift-based product cleanup...');
      int deletedCount = 0;

      // Get all products grouped by SKU and store_id
      final allProducts = await (_db.select(_db.products)
            ..where((p) => p.sku.isNotNull() & p.storeId.isNotNull()))
          .get();

      final Map<String, List<Product>> productsBySkuStore = {};

      for (final product in allProducts) {
        final sku = product.sku!.toLowerCase();
        final storeId = product.storeId;
        final key = '$sku|$storeId';
        productsBySkuStore.putIfAbsent(key, () => []).add(product);
      }

      for (final entry in productsBySkuStore.entries) {
        final products = entry.value;
        if (products.length > 1) {
          debugPrint(
              '  Found ${products.length} products with SKU+store: ${entry.key}');

          // Sort: prefer products with server_id, then by id ascending
          products.sort((a, b) {
            if (a.serverId != null && b.serverId == null) return -1;
            if (a.serverId == null && b.serverId != null) return 1;
            return a.id.compareTo(b.id);
          });

          // Keep the first one, check if others can be deleted
          for (int i = 1; i < products.length; i++) {
            final product = products[i];

            // Check if this product is referenced by any sale_items
            final saleItemCount = await (_db.select(_db.saleItems)
                  ..where((si) => si.productId.equals(product.id)))
                .get();

            if (saleItemCount.isNotEmpty) {
              debugPrint(
                  '    ⚠️ Skipped deleting product id=${product.id} (referenced by ${saleItemCount.length} sale_items)');
              continue;
            }

            await (_db.delete(_db.products)
                  ..where((p) => p.id.equals(product.id)))
                .go();
            debugPrint(
                '    ✅ Deleted duplicate product id=${product.id} (SKU: ${product.sku})');
            deletedCount++;
          }
        }
      }

      debugPrint(
          '🧹 Drift-based product cleanup complete: deleted $deletedCount duplicates');
      return deletedCount;
    });
  }

  /// Remove duplicate users by username, keeping the one with server_id or oldest
  Future<int> cleanupDuplicateUsers() async {
    return await _withDatabaseRetry(() async {
      debugPrint('🧹 Starting Drift-based user cleanup...');
      int deletedCount = 0;

      // Get all users grouped by username
      final allUsers = await (_db.select(_db.users)
            ..where((u) => u.username.isNotNull()))
          .get();

      final Map<String, List<User>> usersByUsername = {};

      for (final user in allUsers) {
        final username = user.username.toLowerCase();
        usersByUsername.putIfAbsent(username, () => []).add(user);
      }

      for (final entry in usersByUsername.entries) {
        final users = entry.value;
        if (users.length > 1) {
          debugPrint(
              '  Found ${users.length} users with username: ${entry.key}');

          // Sort: prefer users with server_id, then by id ascending
          users.sort((a, b) {
            if (a.serverId != null && b.serverId == null) return -1;
            if (a.serverId == null && b.serverId != null) return 1;
            return a.id.compareTo(b.id);
          });

          // Keep the first one, delete the rest
          for (int i = 1; i < users.length; i++) {
            final user = users[i];
            await (_db.delete(_db.users)..where((u) => u.id.equals(user.id)))
                .go();
            debugPrint(
                '    ✅ Deleted duplicate user id=${user.id} (username: ${user.username})');
            deletedCount++;
          }
        }
      }

      debugPrint(
          '🧹 Drift-based user cleanup complete: deleted $deletedCount duplicates');
      return deletedCount;
    });
  }

  /// Remove orphaned sync queue items (referencing deleted entities)
  Future<int> cleanupOrphanedSyncQueue() async {
    return await _withDatabaseRetry(() async {
      debugPrint('🧹 Starting Drift-based sync queue cleanup...');
      int deletedCount = 0;

      // Get all sync queue items
      final allQueueItems = await (_db.select(_db.syncQueue)).get();

      for (final item in allQueueItems) {
        bool shouldDelete = false;

        // Derive table name from resource type (same logic as getPendingSyncItems)
        final resourceType = item.resourceType;
        String tableName = resourceType;
        if (!tableName.endsWith('s') && resourceType != 'analytics_event') {
          tableName = '${tableName}s';
        }
        if (resourceType == 'analytics_event') {
          tableName = 'analytics_events';
        }

        final rowId = item.entityId;

        if (rowId != null) {
          final entityIdInt = int.tryParse(rowId);
          if (entityIdInt != null) {
            if (tableName == 'products') {
              // Check if product exists
              final productExists = await (_db.select(_db.products)
                    ..where((p) => p.id.equals(entityIdInt)))
                  .getSingleOrNull();
              shouldDelete = productExists == null;
            } else if (tableName == 'users') {
              // Check if user exists
              final userExists = await (_db.select(_db.users)
                    ..where((u) => u.id.equals(entityIdInt)))
                  .getSingleOrNull();
              shouldDelete = userExists == null;
            } else if (tableName == 'stores') {
              // Check if store exists
              final storeExists = await (_db.select(_db.stores)
                    ..where((s) => s.id.equals(entityIdInt)))
                  .getSingleOrNull();
              shouldDelete = storeExists == null;
            }
          }
        }

        if (shouldDelete) {
          await (_db.delete(_db.syncQueue)
                ..where((sq) => sq.id.equals(item.id)))
              .go();
          deletedCount++;
        }
      }

      debugPrint(
          '🧹 Drift-based sync queue cleanup complete: deleted $deletedCount orphaned items');
      return deletedCount;
    });
  }
}
