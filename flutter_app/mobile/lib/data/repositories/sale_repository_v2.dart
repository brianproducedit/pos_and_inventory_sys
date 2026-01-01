import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../db/app_database.dart';
import '../../models/receipt_model.dart';
import 'product_repository_v2.dart';

/// Sale repository for local-first sales management (offline checkout).
class SaleRepository extends BaseRepository<Sale> {
  SaleRepository(super.db);

  static const _uuid = Uuid();

  /// Complete a sale entirely offline.
  /// Creates sale record, sale items, and updates product stock atomically.
  Future<Sale> completeSale({
    required int userId,
    required int storeId,
    required double totalAmount,
    required String paymentMethod,
    String? paymentReference,
    required List<SaleItemData> items,
  }) async {
    return await db.transaction(() async {
      final clientId = _uuid.v4();
      final transactionNumber = _generateTransactionNumber();

      // 1. Insert sale record
      final saleId = await db.into(db.sales).insert(SalesCompanion.insert(
            clientId: Value(clientId),
            transactionNumber: transactionNumber,
            userId: userId,
            storeId: storeId,
            totalAmount: totalAmount,
            paymentMethod: paymentMethod,
            paymentReference: Value(paymentReference),
            syncStatus: Value(SyncStatus.pending),
          ));

      // 2. Insert sale items and update stock
      final saleItemsData = <Map<String, dynamic>>[];
      for (final item in items) {
        final itemClientId = _uuid.v4();

        await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
              clientId: Value(itemClientId),
              saleId: saleId,
              productId: item.productId,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              totalPrice: item.quantity * item.unitPrice,
              syncStatus: Value(SyncStatus.pending),
            ));

        // Deduct stock locally
        final product = await (db.select(db.products)
              ..where((p) => p.id.equals(item.productId)))
            .getSingle();

        await (db.update(db.products)
              ..where((p) => p.id.equals(item.productId)))
            .write(ProductsCompanion(
          stockQuantity: Value(product.stockQuantity - item.quantity),
          syncStatus: Value(SyncStatus.pending),
          lastUpdatedAt: Value(DateTime.now()),
        ));

        saleItemsData.add({
          'product_id': product.serverId ?? product.id,
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
          'total_price': item.quantity * item.unitPrice,
        });
      }

      // 3. Enqueue for sync
      await enqueueSync(
        clientTempId: clientId,
        resourceType: 'sale',
        operation: 'create',
        data: {
          'transaction_number': transactionNumber,
          'user_id': userId,
          'store_id': storeId,
          'total_amount': totalAmount,
          'payment_method': paymentMethod,
          'payment_reference': paymentReference,
          'items': saleItemsData,
        },
      );

      return await (db.select(db.sales)..where((s) => s.id.equals(saleId)))
          .getSingle();
    });
  }

  /// Get a sale by local ID with its items.
  Future<SaleWithItems?> getSaleWithItems(int saleId) async {
    final sale = await (db.select(db.sales)..where((s) => s.id.equals(saleId)))
        .getSingleOrNull();

    if (sale == null) return null;

    final items = await (db.select(db.saleItems)
          ..where((si) => si.saleId.equals(saleId)))
        .get();

    return SaleWithItems(sale: sale, items: items);
  }

  /// Watch sales for a specific store.
  Stream<List<Sale>> watchByStore(int storeId) {
    return (db.select(db.sales)..where((s) => s.storeId.equals(storeId)))
        .watch();
  }

  /// Get sales for a specific store.
  Future<List<Sale>> getByStore(int storeId) async {
    return await (db.select(db.sales)..where((s) => s.storeId.equals(storeId)))
        .get();
  }

  /// Get sales within a date range.
  Future<List<Sale>> getByDateRange(DateTime start, DateTime end) async {
    return await (db.select(db.sales)
          ..where((s) => s.createdAt.isBiggerOrEqualValue(start))
          ..where((s) => s.createdAt.isSmallerOrEqualValue(end))
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .get();
  }

  String _generateTransactionNumber() {
    final now = DateTime.now();
    return 'TXN${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '${now.millisecondsSinceEpoch % 100000}';
  }

  /// Generate receipt for a sale
  Future<ReceiptModel> generateReceipt({
    required int saleId,
    String storeName = 'POS Store',
    String? storeAddress,
    String? storePhone,
    String cashierName = 'Cashier',
    double? taxRate,
    String? footerMessage,
  }) async {
    final saleWithItems = await getSaleWithItems(saleId);
    if (saleWithItems == null) {
      throw Exception('Sale not found');
    }

    final sale = saleWithItems.sale;
    final items = saleWithItems.items;

    // Build receipt line items
    final receiptItems = <ReceiptLineItem>[];
    for (final item in items) {
      // Get product name
      final product = await (db.select(db.products)
            ..where((p) => p.id.equals(item.productId)))
          .getSingle();

      receiptItems.add(ReceiptLineItem(
        name: product.name,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        total: item.totalPrice,
      ));
    }

    // Calculate tax if rate provided
    double? taxAmount;
    if (taxRate != null && taxRate > 0) {
      taxAmount = sale.totalAmount * (taxRate / (100 + taxRate));
    }

    final subtotal = taxAmount != null ? sale.totalAmount - taxAmount : sale.totalAmount;

    return ReceiptModel(
      transactionNumber: sale.transactionNumber,
      date: sale.createdAt,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      cashierName: cashierName,
      items: receiptItems,
      subtotal: subtotal,
      taxRate: taxRate,
      taxAmount: taxAmount,
      total: sale.totalAmount,
      paymentMethod: sale.paymentMethod,
      paymentReference: sale.paymentReference,
      footerMessage: footerMessage,
    );
  }
}

/// Data class for sale item input.
class SaleItemData {
  final int productId;
  final int quantity;
  final double unitPrice;

  SaleItemData({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
  });
}

/// Sale with its items for display.
class SaleWithItems {
  final Sale sale;
  final List<SaleItem> items;

  SaleWithItems({required this.sale, required this.items});
}
