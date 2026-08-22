import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../db/app_database.dart';
import 'product_repository_v2.dart';

/// Store repository for local-first store management.
class StoreRepository extends BaseRepository<Store> {
  StoreRepository(super.db);

  static const _uuid = Uuid();

  /// Helper method to execute database operations with retry logic for database_closed exceptions.
  /// This handles cases where the database connection gets closed due to app lifecycle or memory pressure.
  Future<T> _withDatabaseRetry<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on DriftWrappedException catch (e) {
      if (e.toString().contains('database_closed')) {
        debugPrint(
            '🔁 Database connection closed, attempting to reopen and retry');
        try {
          // Force reopen the database connection by accessing it
          await db.customSelect('SELECT 1').get();
          // Retry the operation
          return await operation();
        } catch (retryError) {
          debugPrint(' Database retry failed: $retryError');
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  /// Create a store locally and enqueue for sync.
  Future<Store> create({
    required String name,
    String? location,
    int? createdBy,
  }) async {
    return await _withDatabaseRetry(() async {
      final clientId = _uuid.v4();

      final id = await db.into(db.stores).insert(StoresCompanion.insert(
            clientId: Value(clientId),
            name: name,
            location: Value(location),
            createdBy: Value(createdBy),
            syncStatus: const Value(SyncStatus.pending),
          ));

      await enqueueSync(
        clientTempId: clientId,
        resourceType: 'store',
        operation: 'create',
        data: {
          'name': name,
          'location': location,
          'created_by': createdBy,
        },
      );
      debugPrint(
          'StoreRepository.create: Successfully enqueued sync for store $id with clientId $clientId');

      return await (db.select(db.stores)..where((s) => s.id.equals(id)))
          .getSingle();
    });
  }

  /// Update a store locally and enqueue for sync.
  Future<Store> update(
    int id, {
    String? name,
    String? location,
    bool? isActive,
  }) async {
    return await _withDatabaseRetry(() async {
      final store = await getById(id);
      if (store == null) {
        throw Exception('Store not found');
      }

      await (db.update(db.stores)..where((s) => s.id.equals(id))).write(
        StoresCompanion(
          name: name != null ? Value(name) : const Value.absent(),
          location: location != null ? Value(location) : const Value.absent(),
          isActive: isActive != null ? Value(isActive) : const Value.absent(),
          syncStatus: const Value(SyncStatus.pending),
          lastUpdatedAt: Value(DateTime.now()),
        ),
      );

      final updated = await getById(id);

      await enqueueSync(
        resourceType: 'store',
        operation: 'update',
        entityId: store.serverId?.toString() ?? store.clientId,
        data: {
          'id': store.serverId,
          'client_id': store.clientId,
          if (name != null) 'name': name,
          if (location != null) 'location': location,
          if (isActive != null) 'is_active': isActive,
        },
      );

      return updated!;
    });
  }

  /// Deactivate a store (soft delete - sets is_active to false).
  /// The store remains in the database but is hidden from active store lists.
  /// Use this when you want to preserve store history and related data.
  Future<void> deactivate(int id) async {
    return await _withDatabaseRetry(() async {
      final store = await getById(id);
      if (store == null) return;

      debugPrint(' Deactivating store: id=$id, serverId=${store.serverId}');

      await (db.update(db.stores)..where((s) => s.id.equals(id))).write(
        StoresCompanion(
          isActive: const Value(false),
          syncStatus: const Value(SyncStatus.pending),
          lastUpdatedAt: Value(DateTime.now()),
        ),
      );

      // Sync as an update with is_active = false (soft delete on backend)
      await enqueueSync(
        resourceType: 'store',
        operation: 'update',
        entityId: store.serverId?.toString() ?? store.clientId,
        data: {
          'id': store.serverId,
          'client_id': store.clientId,
          'is_active': false,
        },
      );
    });
  }

  /// Legacy soft delete method - now calls deactivate for backwards compatibility.
  @Deprecated(
      'Use deactivate() for soft delete or hardDelete() for permanent deletion')
  Future<void> delete(int id) async {
    await deactivate(id);
  }

  /// Hard delete a store (permanently remove from local and server databases).
  /// This will:
  /// 1. Enqueue a sync operation to call the /stores/{id}/hard endpoint on the server
  /// 2. Permanently delete the store from the local database
  ///
  /// WARNING: This action cannot be undone. All related data will be deleted.
  Future<void> hardDelete(int id) async {
    return await _withDatabaseRetry(() async {
      final store = await getById(id);
      if (store == null) {
        debugPrint('️ Store not found for hard delete: id=$id');
        return;
      }

      debugPrint(
          '🗑️ Hard deleting store: id=$id, serverId=${store.serverId}, clientId=${store.clientId}');

      // Enqueue hard delete sync operation BEFORE deleting locally
      // The payload contains the server_id which will be used by the sync service
      await enqueueSync(
        resourceType: 'store',
        operation: 'delete', // Sync service will use /hard endpoint for stores
        entityId: store.serverId?.toString() ?? store.clientId,
        data: {
          'id': store.serverId, // Server ID for API call
          'client_id': store.clientId,
          'local_id': id, // Keep track of local ID for reference
        },
      );

      // Now delete locally - this removes the store immediately from the local DB
      await (db.delete(db.stores)..where((s) => s.id.equals(id))).go();
      debugPrint(' Store hard deleted locally: id=$id');
    });
  }

  /// Get a store by local ID.
  Future<Store?> getById(int id) async {
    return await _withDatabaseRetry(() async {
      return await (db.select(db.stores)..where((s) => s.id.equals(id)))
          .getSingleOrNull();
    });
  }

  /// Get a store by server ID.
  Future<Store?> getByServerId(int serverId) async {
    return await _withDatabaseRetry(() async {
      return await (db.select(db.stores)
            ..where((s) => s.serverId.equals(serverId)))
          .getSingleOrNull();
    });
  }

  /// Watch all active stores.
  Stream<List<Store>> watchAll() {
    return (db.select(db.stores)..where((s) => s.isActive.equals(true)))
        .watch();
  }

  /// Watch all stores including inactive ones.
  Stream<List<Store>> watchAllIncludingInactive() {
    return db.select(db.stores).watch();
  }

  /// Get all active stores.
  Future<List<Store>> getAll() async {
    return await _withDatabaseRetry(() async {
      return await (db.select(db.stores)..where((s) => s.isActive.equals(true)))
          .get();
    });
  }

  /// Get all stores including inactive ones.
  Future<List<Store>> getAllIncludingInactive() async {
    return await _withDatabaseRetry(() async {
      return await db.select(db.stores).get();
    });
  }
}
