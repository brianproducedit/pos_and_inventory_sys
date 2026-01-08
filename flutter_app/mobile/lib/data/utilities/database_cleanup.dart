import 'package:flutter/foundation.dart';
import '../../db/app_database.dart';
import '../sync/sync_database_helper.dart';

/// Database cleanup utilities for removing duplicate and orphaned records
class DatabaseCleanup {
  final AppDatabase db;
  late final SyncDatabaseHelper _helper;

  DatabaseCleanup(this.db) {
    _helper = SyncDatabaseHelper(db);
  }

  /// Remove duplicate products, keeping the one with server_id if available
  Future<int> cleanupDuplicateProducts() async {
    return await _helper.cleanupDuplicateProducts();
  }

  /// Remove products that reference non-existent stores (orphaned FK)
  Future<int> cleanupOrphanedProducts() async {
    debugPrint('🧹 Starting orphaned product cleanup...');
    int deletedCount = 0;

    // Get all products with store_id
    final productsWithStore = await (db.select(db.products)
          ..where((p) => p.storeId.isNotNull()))
        .get();

    for (final product in productsWithStore) {
      // Check if the store exists
      final storeExists = await (db.select(db.stores)
            ..where((s) => s.id.equals(product.storeId)))
          .getSingleOrNull();

      if (storeExists == null) {
        debugPrint(
            '  Found orphaned product: id=${product.id}, name=${product.name}, store_id=${product.storeId}');

        await (db.delete(db.products)..where((p) => p.id.equals(product.id)))
            .go();
        debugPrint('    ✅ Deleted orphaned product id=${product.id}');
        deletedCount++;
      }
    }

    debugPrint(
        '🧹 Orphaned product cleanup complete: deleted $deletedCount products');
    return deletedCount;
  }

  /// Remove duplicate users, keeping the one with server_id if available
  Future<int> cleanupDuplicateUsers() async {
    return await _helper.cleanupDuplicateUsers();
  }

  /// Remove orphaned sync queue items (referencing deleted entities)
  Future<int> cleanupOrphanedSyncQueue() async {
    return await _helper.cleanupOrphanedSyncQueue();
  }

  /// Run all cleanup operations
  Future<Map<String, int>> cleanupAll() async {
    debugPrint('🧹🧹🧹 Starting full database cleanup...');

    final results = {
      'duplicate_products': await cleanupDuplicateProducts(),
      'orphaned_products': await cleanupOrphanedProducts(),
      'duplicate_users': await cleanupDuplicateUsers(),
      'orphaned_sync_queue': await cleanupOrphanedSyncQueue(),
    };

    final total = results.values.reduce((a, b) => a + b);
    debugPrint('🧹🧹🧹 Full cleanup complete: deleted $total total records');
    debugPrint('  - Duplicate products: ${results['duplicate_products']}');
    debugPrint('  - Orphaned products: ${results['orphaned_products']}');
    debugPrint('  - Duplicate users: ${results['duplicate_users']}');
    debugPrint('  - Orphaned sync queue: ${results['orphaned_sync_queue']}');

    return results;
  }

  /// Get statistics about potential issues
  Future<Map<String, dynamic>> getDatabaseStats() async {
    final stats = <String, dynamic>{};

    // Count total records using Drift
    stats['total_products'] =
        await (db.select(db.products)).get().then((list) => list.length);
    stats['total_users'] =
        await (db.select(db.users)).get().then((list) => list.length);
    stats['total_stores'] =
        await (db.select(db.stores)).get().then((list) => list.length);
    stats['total_sync_queue'] =
        await (db.select(db.syncQueue)).get().then((list) => list.length);

    // Count products without server_id (not synced)
    stats['unsynced_products'] = await (db.select(db.products)
          ..where((p) => p.serverId.isNull()))
        .get()
        .then((list) => list.length);

    // For duplicate detection, we'd need more complex queries
    // For now, just return basic stats
    stats['duplicate_product_groups'] = 0; // Would need custom query
    stats['orphaned_products'] = 0; // Would need custom query

    return stats;
  }
}
