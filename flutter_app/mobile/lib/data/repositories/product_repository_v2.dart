import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../db/app_database.dart';

/// Base repository interface defining local-first CRUD operations.
/// All repositories follow the pattern: write to local DB immediately, enqueue for sync.
abstract class BaseRepository<T> {
  final AppDatabase db;

  BaseRepository(this.db);

  /// Enqueue a change for background sync.
  Future<void> enqueueSync({
    String? clientTempId,
    required String resourceType,
    required String operation,
    required Map<String, dynamic> data,
    String? entityId,
  }) async {
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
    final clientId = _uuid.v4();

    final id = await db.into(db.products).insert(ProductsCompanion.insert(
          clientId: Value(clientId),
          name: name,
          description: Value(description),
          sku: Value(sku),
          price: Value(price),
          stockQuantity: Value(stockQuantity),
          storeId: storeId,
          syncStatus: Value(SyncStatus.pending),
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
        syncStatus: Value(SyncStatus.pending),
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

  /// Soft delete a product (set isActive = false).
  Future<void> delete(int id) async {
    final product = await getById(id);
    if (product == null) return;

    await (db.update(db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        isActive: const Value(false),
        syncStatus: Value(SyncStatus.pending),
        lastUpdatedAt: Value(DateTime.now()),
      ),
    );

    await enqueueSync(
      resourceType: 'product',
      operation: 'delete',
      entityId: product.serverId?.toString() ?? product.clientId,
      data: {
        'id': product.serverId,
        'client_id': product.clientId,
      },
    );
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
        syncStatus: Value(SyncStatus.pending),
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
}
