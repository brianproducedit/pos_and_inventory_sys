import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../db/app_database.dart';
import 'product_repository_v2.dart';

/// Store repository for local-first store management.
class StoreRepository extends BaseRepository<Store> {
  StoreRepository(super.db);

  static const _uuid = Uuid();

  /// Create a store locally and enqueue for sync.
  Future<Store> create({
    required String name,
    String? location,
    int? createdBy,
  }) async {
    final clientId = _uuid.v4();

    final id = await db.into(db.stores).insert(StoresCompanion.insert(
          clientId: Value(clientId),
          name: name,
          location: Value(location),
          createdBy: Value(createdBy),
          syncStatus: Value(SyncStatus.pending),
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

    return await (db.select(db.stores)..where((s) => s.id.equals(id)))
        .getSingle();
  }

  /// Update a store locally and enqueue for sync.
  Future<Store> update(
    int id, {
    String? name,
    String? location,
    bool? isActive,
  }) async {
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
  }

  /// Soft delete a store.
  Future<void> delete(int id) async {
    final store = await getById(id);
    if (store == null) return;

    await (db.update(db.stores)..where((s) => s.id.equals(id))).write(
      StoresCompanion(
        isActive: const Value(false),
        syncStatus: const Value(SyncStatus.pending),
        lastUpdatedAt: Value(DateTime.now()),
      ),
    );

    await enqueueSync(
      resourceType: 'store',
      operation: 'delete',
      entityId: store.serverId?.toString() ?? store.clientId,
      data: {
        'id': store.serverId,
        'client_id': store.clientId,
      },
    );
  }

  /// Get a store by local ID.
  Future<Store?> getById(int id) async {
    return await (db.select(db.stores)..where((s) => s.id.equals(id)))
        .getSingleOrNull();
  }

  /// Watch all active stores.
  Stream<List<Store>> watchAll() {
    return (db.select(db.stores)..where((s) => s.isActive.equals(true)))
        .watch();
  }

  /// Get all active stores.
  Future<List<Store>> getAll() async {
    return await (db.select(db.stores)..where((s) => s.isActive.equals(true)))
        .get();
  }
}
