import 'package:drift/drift.dart';
import '../../db/app_database.dart';
import 'product_repository_v2.dart';

/// Repository for computing analytics from local sales data
/// Fully offline-capable - no network dependencies
class AnalyticsRepository extends BaseRepository<Sale> {
  AnalyticsRepository(super.db);

  /// Get sales summary for date range
  Future<SalesSummary> getSalesSummary({
    int? storeId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var query = db.select(db.sales);

    // Apply filters
    if (storeId != null) {
      query = query..where((s) => s.storeId.equals(storeId));
    }
    if (startDate != null) {
      query = query..where((s) => s.createdAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query = query..where((s) => s.createdAt.isSmallerOrEqualValue(endDate));
    }

    final sales = await query.get();

    // Compute aggregates
    final totalSales = sales.length;
    final totalRevenue = sales.fold<double>(0, (sum, s) => sum + s.totalAmount);
    final averageOrderValue = totalSales > 0 ? totalRevenue / totalSales : 0.0;

    // Count by payment method
    final cashCount = sales.where((s) => s.paymentMethod == 'cash').length;
    final cardCount = sales.where((s) => s.paymentMethod == 'card').length;
    final mobileCount = sales.where((s) => s.paymentMethod == 'mobile').length;

    return SalesSummary(
      totalSales: totalSales,
      totalRevenue: totalRevenue,
      averageOrderValue: averageOrderValue,
      cashSales: cashCount,
      cardSales: cardCount,
      mobileSales: mobileCount,
      startDate: startDate ?? DateTime.now().subtract(const Duration(days: 30)),
      endDate: endDate ?? DateTime.now(),
    );
  }

  /// Get top products by quantity sold
  Future<List<TopProduct>> getTopProducts({
    int? storeId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 10,
  }) async {
    // Join SaleItems with Products and Sales
    final query = db.select(db.saleItems).join([
      innerJoin(db.products, db.products.id.equalsExp(db.saleItems.productId)),
      innerJoin(db.sales, db.sales.id.equalsExp(db.saleItems.saleId)),
    ]);

    // Apply filters
    if (storeId != null) {
      query.where(db.sales.storeId.equals(storeId));
    }
    if (startDate != null) {
      query.where(db.sales.createdAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where(db.sales.createdAt.isSmallerOrEqualValue(endDate));
    }

    final results = await query.get();

    // Group by product and sum quantities
    final productSales = <int, TopProduct>{};
    for (final row in results) {
      final saleItem = row.readTable(db.saleItems);
      final product = row.readTable(db.products);

      final existing = productSales[product.id];
      if (existing != null) {
        productSales[product.id] = TopProduct(
          productId: product.id,
          productName: product.name,
          quantitySold: existing.quantitySold + saleItem.quantity,
          revenue: existing.revenue + saleItem.totalPrice,
        );
      } else {
        productSales[product.id] = TopProduct(
          productId: product.id,
          productName: product.name,
          quantitySold: saleItem.quantity,
          revenue: saleItem.totalPrice,
        );
      }
    }

    // Sort by quantity and limit
    final topProducts = productSales.values.toList()
      ..sort((a, b) => b.quantitySold.compareTo(a.quantitySold));

    return topProducts.take(limit).toList();
  }

  /// Get sales by time period (daily, weekly, monthly)
  Future<List<SalesByPeriod>> getSalesByPeriod({
    int? storeId,
    DateTime? startDate,
    DateTime? endDate,
    String granularity = 'day', // 'day', 'week', 'month'
  }) async {
    var query = db.select(db.sales);

    if (storeId != null) {
      query = query..where((s) => s.storeId.equals(storeId));
    }
    if (startDate != null) {
      query = query..where((s) => s.createdAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query = query..where((s) => s.createdAt.isSmallerOrEqualValue(endDate));
    }

    final sales = await query.get();

    // Group by period
    final periods = <String, SalesByPeriod>{};
    for (final sale in sales) {
      final periodKey = _getPeriodKey(sale.createdAt, granularity);

      final existing = periods[periodKey];
      if (existing != null) {
        periods[periodKey] = SalesByPeriod(
          period: periodKey,
          count: existing.count + 1,
          revenue: existing.revenue + sale.totalAmount,
          date: existing.date,
        );
      } else {
        periods[periodKey] = SalesByPeriod(
          period: periodKey,
          count: 1,
          revenue: sale.totalAmount,
          date: sale.createdAt,
        );
      }
    }

    return periods.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Get recent sales
  Future<List<Sale>> getRecentSales({
    int? storeId,
    int limit = 10,
  }) async {
    var query = db.select(db.sales)
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)])
      ..limit(limit);

    if (storeId != null) {
      query = query..where((s) => s.storeId.equals(storeId));
    }

    return await query.get();
  }

  /// Get low stock alerts
  Future<List<Product>> getLowStockProducts({
    int? storeId,
    int threshold = 10,
  }) async {
    var query = db.select(db.products)
      ..where((p) => p.stockQuantity.isSmallerOrEqualValue(threshold))
      ..where((p) => p.isActive.equals(true))
      ..orderBy([(p) => OrderingTerm.asc(p.stockQuantity)]);

    if (storeId != null) {
      query = query..where((p) => p.storeId.equals(storeId));
    }

    return await query.get();
  }

  /// Get store comparison data (superadmin only)
  Future<List<StorePerformance>> getStoreComparison({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final stores = await db.select(db.stores).get();
    final performances = <StorePerformance>[];

    for (final store in stores) {
      final summary = await getSalesSummary(
        storeId: store.id,
        startDate: startDate,
        endDate: endDate,
      );

      performances.add(StorePerformance(
        storeId: store.id,
        storeName: store.name,
        totalSales: summary.totalSales,
        totalRevenue: summary.totalRevenue,
        averageOrderValue: summary.averageOrderValue,
      ));
    }

    return performances
      ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
  }

  /// Get payment method breakdown
  Future<Map<String, int>> getPaymentMethodBreakdown({
    int? storeId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var query = db.select(db.sales);

    if (storeId != null) {
      query = query..where((s) => s.storeId.equals(storeId));
    }
    if (startDate != null) {
      query = query..where((s) => s.createdAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query = query..where((s) => s.createdAt.isSmallerOrEqualValue(endDate));
    }

    final sales = await query.get();

    final breakdown = <String, int>{};
    for (final sale in sales) {
      final method = sale.paymentMethod;
      breakdown[method] = (breakdown[method] ?? 0) + 1;
    }

    return breakdown;
  }

  /// Get hourly sales distribution
  Future<Map<int, int>> getHourlySalesDistribution({
    int? storeId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var query = db.select(db.sales);

    if (storeId != null) {
      query = query..where((s) => s.storeId.equals(storeId));
    }
    if (startDate != null) {
      query = query..where((s) => s.createdAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query = query..where((s) => s.createdAt.isSmallerOrEqualValue(endDate));
    }

    final sales = await query.get();

    final hourly = <int, int>{};
    for (final sale in sales) {
      final hour = sale.createdAt.hour;
      hourly[hour] = (hourly[hour] ?? 0) + 1;
    }

    return hourly;
  }

  String _getPeriodKey(DateTime date, String granularity) {
    switch (granularity) {
      case 'day':
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      case 'week':
        final weekOfYear =
            ((date.difference(DateTime(date.year, 1, 1)).inDays) / 7).floor() +
                1;
        return '${date.year}-W${weekOfYear.toString().padLeft(2, '0')}';
      case 'month':
        return '${date.year}-${date.month.toString().padLeft(2, '0')}';
      default:
        return date.toIso8601String();
    }
  }
}

/// Sales summary model
class SalesSummary {
  final int totalSales;
  final double totalRevenue;
  final double averageOrderValue;
  final int cashSales;
  final int cardSales;
  final int mobileSales;
  final DateTime startDate;
  final DateTime endDate;

  SalesSummary({
    required this.totalSales,
    required this.totalRevenue,
    required this.averageOrderValue,
    required this.cashSales,
    required this.cardSales,
    required this.mobileSales,
    required this.startDate,
    required this.endDate,
  });

  Map<String, dynamic> toJson() => {
        'total_sales': totalSales,
        'total_revenue': totalRevenue,
        'average_order_value': averageOrderValue,
        'cash_sales': cashSales,
        'card_sales': cardSales,
        'mobile_sales': mobileSales,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
      };
}

/// Top product model
class TopProduct {
  final int productId;
  final String productName;
  final int quantitySold;
  final double revenue;

  TopProduct({
    required this.productId,
    required this.productName,
    required this.quantitySold,
    required this.revenue,
  });

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': productName,
        'quantity_sold': quantitySold,
        'revenue': revenue,
      };
}

/// Sales by period model
class SalesByPeriod {
  final String period;
  final int count;
  final double revenue;
  final DateTime date;

  SalesByPeriod({
    required this.period,
    required this.count,
    required this.revenue,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'period': period,
        'count': count,
        'revenue': revenue,
        'date': date.toIso8601String(),
      };
}

/// Store performance model
class StorePerformance {
  final int storeId;
  final String storeName;
  final int totalSales;
  final double totalRevenue;
  final double averageOrderValue;

  StorePerformance({
    required this.storeId,
    required this.storeName,
    required this.totalSales,
    required this.totalRevenue,
    required this.averageOrderValue,
  });

  Map<String, dynamic> toJson() => {
        'store_id': storeId,
        'store_name': storeName,
        'total_sales': totalSales,
        'total_revenue': totalRevenue,
        'average_order_value': averageOrderValue,
      };
}
