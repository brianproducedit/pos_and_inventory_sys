import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../db/app_database.dart';

/// Inventory log entry type
enum InventoryLogType {
  adjustment,  // Manual stock adjustment
  sale,        // Stock reduced by sale
  restock,     // Stock added by restock
  transfer,    // Stock transferred between stores
  damaged,     // Stock marked as damaged/lost
  return_,     // Stock returned by customer
}

/// Repository for inventory management and stock tracking
/// Implements local-first pattern with audit trail via InventoryLogs table
class InventoryRepository {
  final AppDatabase db;

  InventoryRepository({required this.db});

  /// Adjust product stock (manual adjustment)
  Future<void> adjustStock({
    required int productId,
    required int quantity,
    required int userId,
    required String reason,
    InventoryLogType type = InventoryLogType.adjustment,
  }) async {
    await db.transaction(() async {
      // 1. Get current product
      final product = await (db.select(db.products)
            ..where((p) => p.id.equals(productId)))
          .getSingle();

      final oldQuantity = product.stockQuantity;
      final newQuantity = oldQuantity + quantity; // quantity can be negative

      // 2. Update product stock
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(ProductsCompanion(
        stockQuantity: Value(newQuantity),
        syncStatus: Value(SyncStatus.pending),
        lastUpdatedAt: Value(DateTime.now()),
      ));

      // 3. Log the inventory change
      await _logInventoryChange(
        productId: productId,
        oldQuantity: oldQuantity,
        newQuantity: newQuantity,
        changeAmount: quantity,
        type: type,
        userId: userId,
        reason: reason,
      );

      // 4. Enqueue for sync
      await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
            resourceType: 'product',
            operation: 'update',
            entityId: Value(product.serverId?.toString() ?? product.clientId),
            payloadJson: jsonEncode({
              'id': product.serverId,
              'client_id': product.clientId,
              'stock_quantity': newQuantity,
              'inventory_log': {
                'type': type.name,
                'old_quantity': oldQuantity,
                'new_quantity': newQuantity,
                'change_amount': quantity,
                'reason': reason,
                'user_id': userId,
              },
            }),
          ));
    });
  }

  /// Restock product (add inventory)
  Future<void> restock({
    required int productId,
    required int quantity,
    required int userId,
    String reason = 'Restock',
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Restock quantity must be positive');
    }

    await adjustStock(
      productId: productId,
      quantity: quantity,
      userId: userId,
      reason: reason,
      type: InventoryLogType.restock,
    );
  }

  /// Mark stock as damaged/lost (reduce inventory)
  Future<void> markDamaged({
    required int productId,
    required int quantity,
    required int userId,
    required String reason,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Damaged quantity must be positive');
    }

    await adjustStock(
      productId: productId,
      quantity: -quantity, // Negative to reduce stock
      userId: userId,
      reason: reason,
      type: InventoryLogType.damaged,
    );
  }

  /// Process customer return (add inventory back)
  Future<void> processReturn({
    required int productId,
    required int quantity,
    required int userId,
    required String reason,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Return quantity must be positive');
    }

    await adjustStock(
      productId: productId,
      quantity: quantity,
      userId: userId,
      reason: reason,
      type: InventoryLogType.return_,
    );
  }

  /// Transfer stock between stores
  Future<void> transferStock({
    required int productId,
    required int fromStoreId,
    required int toStoreId,
    required int quantity,
    required int userId,
    String? notes,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Transfer quantity must be positive');
    }

    // TODO: When multi-store support is fully implemented,
    // this will need to handle products in different stores
    // For now, just log the transfer

    await adjustStock(
      productId: productId,
      quantity: -quantity, // Remove from current store
      userId: userId,
      reason: 'Transferred to store $toStoreId${notes != null ? ': $notes' : ''}',
      type: InventoryLogType.transfer,
    );
  }

  /// Log inventory change in InventoryLogs table
  Future<void> _logInventoryChange({
    required int productId,
    required int oldQuantity,
    required int newQuantity,
    required int changeAmount,
    required InventoryLogType type,
    required int userId,
    required String reason,
  }) async {
    final clientId = const Uuid().v4();

    await db.into(db.inventoryLogs).insert(InventoryLogsCompanion.insert(
          clientId: Value(clientId),
          productId: productId,
          userId: userId,
          quantityChange: changeAmount,
          reason: '$type: $reason',
          syncStatus: Value(SyncStatus.pending),
        ));
  }

  /// Get inventory logs for a product
  Stream<List<InventoryLog>> watchProductLogs(int productId) {
    return (db.select(db.inventoryLogs)
          ..where((l) => l.productId.equals(productId))
          ..orderBy([(l) => OrderingTerm.desc(l.createdAt)]))
        .watch();
  }

  /// Get recent inventory logs (last N entries)
  Stream<List<InventoryLog>> watchRecentLogs({int limit = 50}) {
    return (db.select(db.inventoryLogs)
          ..orderBy([(l) => OrderingTerm.desc(l.createdAt)])
          ..limit(limit))
        .watch();
  }

  /// Get inventory logs by type
  Stream<List<InventoryLog>> watchLogsByType(InventoryLogType type) {
    return (db.select(db.inventoryLogs)
          ..where((l) => l.reason.contains(type.name))
          ..orderBy([(l) => OrderingTerm.desc(l.createdAt)]))
        .watch();
  }

  /// Get inventory logs by user
  Stream<List<InventoryLog>> watchLogsByUser(int userId) {
    return (db.select(db.inventoryLogs)
          ..where((l) => l.userId.equals(userId))
          ..orderBy([(l) => OrderingTerm.desc(l.createdAt)]))
        .watch();
  }

  /// Get inventory logs by date range
  Future<List<InventoryLog>> getLogsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    return await (db.select(db.inventoryLogs)
          ..where((l) => l.createdAt.isBiggerOrEqualValue(startDate))
          ..where((l) => l.createdAt.isSmallerOrEqualValue(endDate))
          ..orderBy([(l) => OrderingTerm.desc(l.createdAt)]))
        .get();
  }

  /// Get low stock products (stock below threshold)
  Future<List<Product>> getLowStockProducts({int threshold = 10}) async {
    return await (db.select(db.products)
          ..where((p) => p.stockQuantity.isSmallerOrEqualValue(threshold))
          ..where((p) => p.isActive.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.stockQuantity)]))
        .get();
  }

  /// Watch low stock products
  Stream<List<Product>> watchLowStockProducts({int threshold = 10}) {
    return (db.select(db.products)
          ..where((p) => p.stockQuantity.isSmallerOrEqualValue(threshold))
          ..where((p) => p.isActive.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.stockQuantity)]))
        .watch();
  }

  /// Get out of stock products
  Future<List<Product>> getOutOfStockProducts() async {
    return await (db.select(db.products)
          ..where((p) => p.stockQuantity.equals(0))
          ..where((p) => p.isActive.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .get();
  }

  /// Watch out of stock products
  Stream<List<Product>> watchOutOfStockProducts() {
    return (db.select(db.products)
          ..where((p) => p.stockQuantity.equals(0))
          ..where((p) => p.isActive.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  /// Get inventory summary statistics
  Future<InventorySummary> getInventorySummary({int? storeId}) async {
    var query = db.select(db.products)
      ..where((p) => p.isActive.equals(true));

    if (storeId != null) {
      query = query..where((p) => p.storeId.equals(storeId));
    }

    final products = await query.get();

    final totalProducts = products.length;
    final totalStockValue = products.fold<double>(
      0,
      (sum, product) => sum + (product.price * product.stockQuantity),
    );
    final lowStockCount =
        products.where((p) => p.stockQuantity <= 10).length;
    final outOfStockCount = products.where((p) => p.stockQuantity == 0).length;
    final totalStockUnits =
        products.fold<int>(0, (sum, product) => sum + product.stockQuantity);

    return InventorySummary(
      totalProducts: totalProducts,
      totalStockValue: totalStockValue,
      lowStockCount: lowStockCount,
      outOfStockCount: outOfStockCount,
      totalStockUnits: totalStockUnits,
    );
  }

  /// Bulk stock adjustment (for multiple products at once)
  Future<void> bulkAdjustStock({
    required List<StockAdjustment> adjustments,
    required int userId,
    required String reason,
  }) async {
    await db.transaction(() async {
      for (final adjustment in adjustments) {
        await adjustStock(
          productId: adjustment.productId,
          quantity: adjustment.quantity,
          userId: userId,
          reason: reason,
          type: adjustment.type,
        );
      }
    });
  }
}

/// Stock adjustment model for bulk operations
class StockAdjustment {
  final int productId;
  final int quantity;
  final InventoryLogType type;

  StockAdjustment({
    required this.productId,
    required this.quantity,
    this.type = InventoryLogType.adjustment,
  });
}

/// Inventory summary statistics
class InventorySummary {
  final int totalProducts;
  final double totalStockValue;
  final int lowStockCount;
  final int outOfStockCount;
  final int totalStockUnits;

  InventorySummary({
    required this.totalProducts,
    required this.totalStockValue,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.totalStockUnits,
  });
}
