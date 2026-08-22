import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../db/app_database.dart';

/// Base repository interface defining local-first CRUD operations.
/// All repositories follow the pattern: write to local DB immediately, enqueue for sync.
abstract class BaseRepository<T> {
  final AppDatabase db;

  BaseRepository(this.db);

  /// Helper method to execute database operations with retry logic for database_closed exceptions.
  /// This handles cases where the database connection gets closed due to app lifecycle or memory pressure.
  Future<R> _withDatabaseRetry<R>(Future<R> Function() operation) async {
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

  /// Enqueue a change for background sync.
  Future<void> enqueueSync({
    String? clientTempId,
    required String resourceType,
    required String operation,
    required Map<String, dynamic> data,
    String? entityId,
  }) async {
    debugPrint(
        'BaseRepository.enqueueSync: Enqueuing $operation on $resourceType, tempId=$clientTempId, entityId=$entityId');
    await _withDatabaseRetry(() async {
      await db.enqueueChange(
        clientTempId: clientTempId,
        resourceType: resourceType,
        operation: operation,
        entityId: entityId,
        payloadJson: jsonEncode({
          'resource_type': resourceType,
          'operation': operation,
          if (clientTempId != null) 'temp_id': clientTempId,
          if (entityId != null) 'id': entityId,
          'data': data,
        }),
      );
    });
    debugPrint('BaseRepository.enqueueSync: Successfully enqueued change');
  }
}

/// Product repository implementing local-first product management.
class ProductRepository extends BaseRepository<Product> {
  ProductRepository(super.db);

  static const _uuid = Uuid();

  /// Create a product locally and enqueue for sync.
  /// Returns immediately without awaiting network.
  Future<Product> create({
    required String name,
    String? description,
    String? sku,
    required double price,
    required int stockQuantity,
    required int storeId,
  }) async {
    return await _withDatabaseRetry(() async {
      // Check for existing product to prevent duplicates
      Product? existing;
      if (sku != null && sku.isNotEmpty) {
        // If SKU is provided, check for existing product with same SKU
        existing = await (db.select(db.products)
              ..where((p) => p.sku.equals(sku)))
            .getSingleOrNull();
      } else {
        // If no SKU, check for existing product with same name and store
        existing = await (db.select(db.products)
              ..where((p) => p.name.equals(name))
              ..where((p) => p.storeId.equals(storeId)))
            .getSingleOrNull();
      }

      if (existing != null) {
        // Return existing product instead of creating duplicate
        return existing;
      }

      final clientId = _uuid.v4();

      final id = await db.into(db.products).insert(ProductsCompanion.insert(
            clientId: Value(clientId),
            name: name,
            description: Value(description),
            sku: Value(sku),
            price: Value(price),
            stockQuantity: Value(stockQuantity),
            storeId: storeId,
            syncStatus: const Value(SyncStatus.pending),
          ));

      // Enqueue for background sync
      await enqueueSync(
        clientTempId: clientId,
        resourceType: 'product',
        operation: 'create',
        data: {
          'name': name,
          'description': description,
          'sku': sku,
          'price': price,
          'stock_quantity': stockQuantity,
          'store_id': storeId,
        },
      );

      return await (db.select(db.products)..where((p) => p.id.equals(id)))
          .getSingle();
    });
  }

  /// Update a product locally and enqueue for sync.
  Future<Product> update(
    int id, {
    String? name,
    String? description,
    String? sku,
    double? price,
    int? stockQuantity,
    bool? isActive,
  }) async {
    final product = await getById(id);
    if (product == null) {
      throw Exception('Product not found');
    }

    await (db.update(db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        description:
            description != null ? Value(description) : const Value.absent(),
        sku: sku != null ? Value(sku) : const Value.absent(),
        price: price != null ? Value(price) : const Value.absent(),
        stockQuantity:
            stockQuantity != null ? Value(stockQuantity) : const Value.absent(),
        isActive: isActive != null ? Value(isActive) : const Value.absent(),
        syncStatus: const Value(SyncStatus.pending),
        lastUpdatedAt: Value(DateTime.now()),
      ),
    );

    final updated = await getById(id);

    // Enqueue for sync
    await enqueueSync(
      resourceType: 'product',
      operation: 'update',
      entityId: product.serverId?.toString() ?? product.clientId,
      data: {
        'id': product.serverId,
        'client_id': product.clientId,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (sku != null) 'sku': sku,
        if (price != null) 'price': price,
        if (stockQuantity != null) 'stock_quantity': stockQuantity,
        if (isActive != null) 'is_active': isActive,
      },
    );

    return updated!;
  }

  /// Hard delete a product (permanently remove from local DB and enqueue delete for server if necessary).
  ///
  /// This intentionally performs a permanent deletion rather than a soft-deactivate
  /// to avoid ambiguity and to ensure server-side deletes are requested when
  /// the product already exists on the server. Attempts to delete a product
  /// that is referenced by existing sales will fail to prevent FK constraint
  /// violations.
  Future<void> delete(int id) async {
    final product = await getById(id);
    if (product == null) return;

    // Prevent deletion if any sale_items reference this product
    final referencing = await (db.select(db.saleItems)
          ..where((s) => s.productId.equals(id)))
        .get();
    if (referencing.isNotEmpty) {
      throw Exception(
          'Cannot delete product $id: referenced by existing sales');
    }

    // If the product has a server_id, enqueue a delete operation so the server
    // can remove it as well. For local-only products (no server_id), no server
    // action is necessary; the local row will simply be removed.
    if (product.serverId != null) {
      await enqueueSync(
        resourceType: 'product',
        operation: 'delete',
        entityId: product.serverId!.toString(),
        data: {
          'id': product.serverId,
          'client_id': product.clientId,
        },
      );
    }

    // Finally, remove the product locally (hard delete)
    await (db.delete(db.products)..where((p) => p.id.equals(id))).go();
  }

  /// Get a product by local ID.
  Future<Product?> getById(int id) async {
    return await (db.select(db.products)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  /// Watch all active products (reactive stream).
  Stream<List<Product>> watchAll({int? storeId}) {
    var query = db.select(db.products)..where((p) => p.isActive.equals(true));

    if (storeId != null) {
      query = query..where((p) => p.storeId.equals(storeId));
    }

    return query.watch();
  }

  /// Get all active products (one-time fetch).
  Future<List<Product>> getAll({int? storeId}) async {
    var query = db.select(db.products)..where((p) => p.isActive.equals(true));

    if (storeId != null) {
      query = query..where((p) => p.storeId.equals(storeId));
    }

    return await query.get();
  }

  /// Update stock quantity (used during sales).
  Future<void> updateStock(int productId, int quantityChange) async {
    final product = await getById(productId);
    if (product == null) return;

    final newQuantity = product.stockQuantity + quantityChange;

    await (db.update(db.products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(
        stockQuantity: Value(newQuantity),
        syncStatus: const Value(SyncStatus.pending),
        lastUpdatedAt: Value(DateTime.now()),
      ),
    );

    // Stock changes are synced via product update
    await enqueueSync(
      resourceType: 'product',
      operation: 'update',
      entityId: product.serverId?.toString() ?? product.clientId,
      data: {
        'id': product.serverId,
        'client_id': product.clientId,
        'stock_quantity': newQuantity,
      },
    );
  }

  /// Watch products with low stock (below threshold).
  Stream<List<Product>> watchLowStock({int? storeId, int threshold = 10}) {
    var query = db.select(db.products)
      ..where((p) => p.isActive.equals(true))
      ..where((p) => p.stockQuantity.isSmallerOrEqualValue(threshold));

    if (storeId != null) {
      query = query..where((p) => p.storeId.equals(storeId));
    }

    return query.watch();
  }

  /// Activate a product (set isActive = true).
  Future<void> activate(int id) async {
    await update(id, isActive: true);
  }

  /// Deactivate a product (set isActive = false).
  Future<void> deactivate(int id) async {
    await update(id, isActive: false);
  }

  /// Search products by name (case-insensitive).
  Future<List<Product>> search(String query, {int? storeId}) async {
    var dbQuery = db.select(db.products)
      ..where((p) => p.isActive.equals(true))
      ..where((p) => p.name.lower().contains(query.toLowerCase()));

    if (storeId != null) {
      dbQuery = dbQuery..where((p) => p.storeId.equals(storeId));
    }

    return await dbQuery.get();
  }

  /// Get a product by SKU.
  Future<Product?> getBySku(String sku) async {
    return await (db.select(db.products)
          ..where((p) => p.sku.equals(sku))
          ..where((p) => p.isActive.equals(true)))
        .getSingleOrNull();
  }
}
