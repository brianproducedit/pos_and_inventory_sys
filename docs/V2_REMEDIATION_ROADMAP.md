# V2 Offline-First Remediation Roadmap

**Created:** January 2, 2026  
**Target Completion:** January 9, 2026 (1 week sprint)  
**Status:** 🚧 IN PROGRESS

---

## Executive Summary

This roadmap addresses the critical gaps identified in the V2 Offline-First Audit Report. The system's core infrastructure is complete, but several screens still depend on V1 API-first services. This document provides a detailed, day-by-day plan to achieve full offline capability.

**Total Effort:** 18-24 hours (distributed over 1 week)  
**Priority:** HIGH - Blocks production deployment

---

## Sprint Overview

| Day | Focus Area | Estimated Hours | Deliverables |
|-----|-----------|-----------------|--------------|
| Day 1 | Analytics Repository | 4-6 hours | AnalyticsRepository_v2 implemented |
| Day 2 | Analytics UI Migration | 3-4 hours | AnalyticsProvider uses V2 |
| Day 3 | Sales History & Receipts | 4-5 hours | Both screens use V2 |
| Day 4 | Store & Settings | 3-4 hours | StoreProvider migration |
| Day 5 | Cleanup & Testing | 4-6 hours | Remove V1, integration tests |

---

## Day 1: Create AnalyticsRepository_v2

**Duration:** 4-6 hours  
**Priority:** CRITICAL

### Tasks

#### Task 1.1: Create AnalyticsRepository_v2 Class
**File:** `flutter_app/mobile/lib/data/repositories/analytics_repository_v2.dart`

```dart
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
    // Join SaleItems with Products
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

    return periods.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
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

    return performances..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
  }

  String _getPeriodKey(DateTime date, String granularity) {
    switch (granularity) {
      case 'day':
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      case 'week':
        final weekOfYear = ((date.difference(DateTime(date.year, 1, 1)).inDays) / 7).floor() + 1;
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
}
```

**Estimated Time:** 3-4 hours

---

#### Task 1.2: Register Repository in main.dart
**File:** `flutter_app/mobile/lib/main.dart`

Add after other V2 repositories:
```dart
Provider<v2.AnalyticsRepository>(
    create: (context) =>
        v2.AnalyticsRepository(context.read<AppDatabase>())),
```

**Estimated Time:** 5 minutes

---

#### Task 1.3: Create Unit Tests
**File:** `flutter_app/mobile/test/repositories/analytics_repository_v2_test.dart`

```dart
void main() {
  late AppDatabase db;
  late AnalyticsRepository repo;

  setUp(() async {
    db = AppDatabase.inMemory();
    repo = AnalyticsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('getSalesSummary', () {
    test('calculates totals correctly', () async {
      // Insert test data
      // Verify summary calculations
    });

    test('filters by store', () async {
      // Test store filtering
    });

    test('filters by date range', () async {
      // Test date filtering
    });
  });

  group('getTopProducts', () {
    test('returns products sorted by quantity', () async {
      // Test top products ranking
    });

    test('respects limit parameter', () async {
      // Test limit enforcement
    });
  });
}
```

**Estimated Time:** 1-2 hours

---

## Day 2: Migrate AnalyticsProvider to V2

**Duration:** 3-4 hours  
**Priority:** HIGH

### Tasks

#### Task 2.1: Update AnalyticsProvider
**File:** `flutter_app/mobile/lib/providers/analytics_provider.dart`

Replace V1 dependencies with V2:

```dart
class AnalyticsProvider with ChangeNotifier {
  final v2.AnalyticsRepository _analyticsRepo;
  final v2.SaleRepository _saleRepo;
  
  AnalyticsProvider({
    required v2.AnalyticsRepository analyticsRepo,
    required v2.SaleRepository saleRepo,
  }) : _analyticsRepo = analyticsRepo,
       _saleRepo = saleRepo;

  // Replace API calls with local queries
  Future<void> loadAnalytics({int? storeId}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Get summary from local data
      final summary = await _analyticsRepo.getSalesSummary(
        storeId: storeId,
        startDate: DateTime.now().subtract(const Duration(days: 30)),
        endDate: DateTime.now(),
      );

      _salesData = {
        'total_sales': summary.totalSales,
        'total_revenue': summary.totalRevenue,
        'average_order_value': summary.averageOrderValue,
        'cash_sales': summary.cashSales,
        'card_sales': summary.cardSales,
        'mobile_sales': summary.mobileSales,
      };

      // Get top products
      final topProducts = await _analyticsRepo.getTopProducts(
        storeId: storeId,
        limit: 10,
      );

      _topProducts = topProducts.map((p) => {
        'product_name': p.productName,
        'quantity_sold': p.quantitySold,
        'revenue': p.revenue,
      }).toList();

      // Get recent sales
      final recentSales = await _saleRepo.getByStore(storeId ?? 0);
      _recentSales = recentSales.take(10).map((s) => {
        'id': s.id,
        'transaction_number': s.transactionNumber,
        'total_amount': s.totalAmount,
        'payment_method': s.paymentMethod,
        'created_at': s.createdAt.toIso8601String(),
      }).toList();

      // Get low stock alerts
      final lowStock = await _analyticsRepo.getLowStockProducts(
        storeId: storeId,
      );

      _inventoryAlerts = lowStock.map((p) => {
        'product_name': p.name,
        'stock_quantity': p.stockQuantity,
        'price': p.price,
      }).toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load analytics: $e';
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

**Estimated Time:** 2-3 hours

---

#### Task 2.2: Update main.dart Provider Registration
**File:** `flutter_app/mobile/lib/main.dart`

```dart
ChangeNotifierProvider(
  create: (context) => AnalyticsProvider(
    analyticsRepo: context.read<v2.AnalyticsRepository>(),
    saleRepo: context.read<v2.SaleRepository>(),
  ),
),
```

**Estimated Time:** 5 minutes

---

#### Task 2.3: Test Analytics Screen
Manual testing checklist:
- [ ] Load analytics offline
- [ ] View sales summary
- [ ] View top products
- [ ] View recent sales
- [ ] View low stock alerts
- [ ] Switch stores (admin/superadmin)
- [ ] Cross-store analytics (superadmin)

**Estimated Time:** 30 minutes

---

## Day 3: Migrate Sales History & Receipts

**Duration:** 4-5 hours  
**Priority:** HIGH

### Tasks

#### Task 3.1: Update SalesHistoryScreen
**File:** `flutter_app/mobile/lib/screens/sales_history_screen.dart`

Replace TransactionRepository with SaleRepository_v2:

```dart
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final saleRepo = context.read<v2.SaleRepository>();
    final storeProvider = context.watch<StoreProvider>();
    final storeId = _parseStoreId(storeProvider.currentStore?['id']);

    return Scaffold(
      appBar: AppBar(title: const Text('Sales History')),
      body: StreamBuilder<List<Sale>>(
        stream: storeId != null 
          ? saleRepo.watchByStore(storeId)
          : Stream.value([]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final sales = snapshot.data ?? [];

          if (sales.isEmpty) {
            return const Center(child: Text('No sales yet'));
          }

          return ListView.builder(
            itemCount: sales.length,
            itemBuilder: (context, index) {
              final sale = sales[index];
              return ListTile(
                title: Text(sale.transactionNumber),
                subtitle: Text(
                  '${sale.paymentMethod} - ${_formatDate(sale.createdAt)}',
                ),
                trailing: Text(
                  '\$${sale.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                onTap: () => _viewReceipt(context, sale.id),
              );
            },
          );
        },
      ),
    );
  }

  void _viewReceipt(BuildContext context, int saleId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(saleId: saleId),
      ),
    );
  }
}
```

**Estimated Time:** 1-2 hours

---

#### Task 3.2: Update ReceiptScreen
**File:** `flutter_app/mobile/lib/screens/receipt_screen.dart`

Use SaleRepository_v2 for data fetching:

```dart
class ReceiptScreen extends StatefulWidget {
  final int saleId;

  const ReceiptScreen({super.key, required this.saleId});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  late Future<ReceiptModel> _receiptFuture;

  @override
  void initState() {
    super.initState();
    _loadReceipt();
  }

  void _loadReceipt() {
    final saleRepo = context.read<v2.SaleRepository>();
    final settingsRepo = context.read<v2.SettingsRepository>();

    _receiptFuture = Future(() async {
      final storeName = await settingsRepo.getStoreName() ?? 'POS Store';
      final storeAddress = await settingsRepo.getStoreAddress();
      final storePhone = await settingsRepo.getStorePhone();
      final footerMessage = await settingsRepo.getReceiptFooter();
      final taxRate = await settingsRepo.getTaxRate();

      return await saleRepo.generateReceipt(
        saleId: widget.saleId,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        footerMessage: footerMessage,
        taxRate: taxRate > 0 ? taxRate : null,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printReceipt,
          ),
        ],
      ),
      body: FutureBuilder<ReceiptModel>(
        future: _receiptFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final receipt = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  receipt.storeName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (receipt.storeAddress != null)
                  Text(receipt.storeAddress!),
                if (receipt.storePhone != null)
                  Text(receipt.storePhone!),
                const Divider(),
                Text('Transaction: ${receipt.transactionNumber}'),
                Text('Date: ${_formatDate(receipt.date)}'),
                Text('Cashier: ${receipt.cashierName}'),
                const Divider(),
                ...receipt.items.map((item) => _buildReceiptItem(item)),
                const Divider(),
                _buildTotal('Subtotal:', receipt.subtotal),
                if (receipt.taxAmount != null)
                  _buildTotal('Tax (${receipt.taxRate}%):', receipt.taxAmount!),
                _buildTotal('Total:', receipt.total, isBold: true),
                const Divider(),
                Text('Payment: ${receipt.paymentMethod}'),
                if (receipt.paymentReference != null)
                  Text('Ref: ${receipt.paymentReference}'),
                const SizedBox(height: 20),
                if (receipt.footerMessage != null)
                  Text(
                    receipt.footerMessage!,
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _printReceipt() async {
    final printerService = context.read<BluetoothPrinterService>();
    final receipt = await _receiptFuture;

    try {
      await printerService.printReceipt(receipt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt sent to printer')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e')),
        );
      }
    }
  }
}
```

**Estimated Time:** 1-2 hours

---

#### Task 3.3: Update ReceiptsProvider
**File:** `flutter_app/mobile/lib/providers/receipts_provider.dart`

Replace mock data with actual repository:

```dart
class ReceiptsProvider with ChangeNotifier {
  final v2.SaleRepository _saleRepo;
  StreamSubscription<List<Sale>>? _subscription;
  List<Sale> _receipts = [];

  ReceiptsProvider({required v2.SaleRepository saleRepo})
      : _saleRepo = saleRepo;

  List<Sale> get receipts => _receipts;

  void watchReceipts({int? storeId}) {
    _subscription?.cancel();
    _subscription = (storeId != null
            ? _saleRepo.watchByStore(storeId)
            : Stream.value([]))
        .listen((sales) {
      _receipts = sales;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
```

**Estimated Time:** 30 minutes

---

#### Task 3.4: Update main.dart Registration
**File:** `flutter_app/mobile/lib/main.dart`

```dart
ChangeNotifierProvider(
  create: (context) => ReceiptsProvider(
    saleRepo: context.read<v2.SaleRepository>(),
  ),
),
```

**Estimated Time:** 5 minutes

---

## Day 4: Migrate Store & Settings Providers

**Duration:** 3-4 hours  
**Priority:** MEDIUM

### Tasks

#### Task 4.1: Update StoreProvider
**File:** `flutter_app/mobile/lib/providers/store_provider.dart`

Replace API calls with StoreRepository_v2:

```dart
class StoreProvider with ChangeNotifier {
  final v2.StoreRepository _storeRepo;
  StreamSubscription<List<Store>>? _subscription;
  
  List<Store> _stores = [];
  Store? _currentStore;

  StoreProvider({required v2.StoreRepository storeRepo})
      : _storeRepo = storeRepo {
    _watchStores();
  }

  List<Store> get stores => _stores;
  Store? get currentStore => _currentStore;

  void _watchStores() {
    _subscription = _storeRepo.watchAll().listen((stores) {
      _stores = stores;
      
      // Auto-select first store if none selected
      if (_currentStore == null && stores.isNotEmpty) {
        _currentStore = stores.first;
      }
      
      notifyListeners();
    });
  }

  Future<void> switchStore(int storeId) async {
    final store = _stores.firstWhere((s) => s.id == storeId);
    _currentStore = store;
    notifyListeners();
  }

  Future<void> createStore({
    required String name,
    String? location,
    int? createdBy,
  }) async {
    await _storeRepo.create(
      name: name,
      location: location,
      createdBy: createdBy,
    );
    // Stream will auto-update
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
```

**Estimated Time:** 2 hours

---

#### Task 4.2: Update SettingsProvider
**File:** `flutter_app/mobile/lib/providers/settings_provider.dart`

Use SettingsRepository_v2:

```dart
class SettingsProvider with ChangeNotifier {
  final v2.SettingsRepository _settingsRepo;

  SettingsProvider({required v2.SettingsRepository settingsRepo})
      : _settingsRepo = settingsRepo;

  // All methods now use _settingsRepo instead of API calls
  Future<String> getThemeMode() => _settingsRepo.getThemeMode();
  Future<void> setThemeMode(String mode) async {
    await _settingsRepo.setThemeMode(mode);
    notifyListeners();
  }

  // ... similar for all settings
}
```

**Estimated Time:** 1 hour

---

#### Task 4.3: Update main.dart Registration
**File:** `flutter_app/mobile/lib/main.dart`

```dart
ChangeNotifierProvider(
  create: (context) => StoreProvider(
    storeRepo: context.read<v2.StoreRepository>(),
  ),
),

ChangeNotifierProvider(
  create: (context) => SettingsProvider(
    settingsRepo: context.read<v2.SettingsRepository>(),
  ),
),
```

**Estimated Time:** 10 minutes

---

## Day 5: Cleanup & Testing

**Duration:** 4-6 hours  
**Priority:** HIGH

### Tasks

#### Task 5.1: Remove V1 Providers
**File:** `flutter_app/mobile/lib/main.dart`

Remove these providers:
- `InventoryProvider` (V1)
- `PosProvider` (V1)
- `ProductRepository` (V1)
- `TransactionRepository` (V1)
- `SalesService`
- `ProductService`

**Estimated Time:** 30 minutes

---

#### Task 5.2: Rename V2 Classes
Remove `_v2` suffix:
- `ProductRepository_v2` → `ProductRepository`
- `PosProviderV2` → `PosProvider`
- `InventoryProviderV2` → `InventoryProvider`

**Estimated Time:** 1 hour

---

#### Task 5.3: Integration Testing
Create comprehensive offline test suite:

**File:** `flutter_app/mobile/test/integration/offline_flow_test.dart`

```dart
void main() {
  testWidgets('Complete offline workflow', (tester) async {
    // 1. Login offline
    // 2. Create product
    // 3. Complete sale
    // 4. View receipt
    // 5. View analytics
    // 6. View sales history
    // 7. Create user
    // 8. Verify all data in local DB
  });

  testWidgets('Sync after reconnection', (tester) async {
    // 1. Perform offline operations
    // 2. Simulate reconnection
    // 3. Trigger sync
    // 4. Verify data synced to server
  });
}
```

**Estimated Time:** 2-3 hours

---

#### Task 5.4: Manual Testing Checklist

| # | Test Scenario | Expected Result | Pass/Fail |
|---|---------------|-----------------|-----------|
| 1 | Login offline (after first online) | Success with cached credentials | |
| 2 | Create product offline | Appears immediately in list | |
| 3 | Update product offline | Changes visible instantly | |
| 4 | Delete product offline | Removed from list | |
| 5 | Create ghost user offline | Can login immediately | |
| 6 | Complete sale offline | Stock deducted, receipt available | |
| 7 | View sales history offline | Shows all local sales | |
| 8 | View analytics offline | Computed from local data | |
| 9 | View receipt offline | Full receipt displayed | |
| 10 | Print receipt offline | Queued if printer unavailable | |
| 11 | Adjust inventory offline | Stock updated immediately | |
| 12 | Change settings offline | Applied immediately | |
| 13 | Sync when online | All changes pushed to server | |
| 14 | Resolve sync conflict | UI allows manual resolution | |
| 15 | Background sync | Automatic sync every 15 min | |

**Estimated Time:** 1-2 hours

---

#### Task 5.5: Update Documentation
Update these files:
- [V2_OFFLINE_FIRST_ROADMAP.md](V2_OFFLINE_FIRST_ROADMAP.md) - Mark complete
- [V2_OFFLINE_FIRST_AUDIT_REPORT.md](V2_OFFLINE_FIRST_AUDIT_REPORT.md) - Update status
- [README.md](../README.md) - Add V2 feature highlights
- [user_guide_offline_usage.md](user_guide_offline_usage.md) - Update instructions

**Estimated Time:** 30 minutes

---

## Success Criteria

Before marking V2 migration complete, verify:

- [ ] All screens work offline (no network dependency)
- [ ] All CRUD operations succeed offline
- [ ] Analytics computed from local data
- [ ] Sales history displays local sales
- [ ] Receipts generated locally
- [ ] Settings persist locally
- [ ] Background sync functional
- [ ] Conflict resolution working
- [ ] All integration tests passing
- [ ] Manual test checklist 100% pass
- [ ] V1 providers removed
- [ ] Documentation updated

---

## Rollback Plan

If critical issues discovered:

1. **Immediate:** Revert to last stable commit
2. **Within 24 hours:** Fix forward if issue isolated
3. **Beyond 24 hours:** Consider rollback and re-plan

**Git Strategy:**
```bash
# Create feature branch for each day's work
git checkout -b feature/v2-day1-analytics-repo
# Commit frequently with descriptive messages
git commit -m "feat(analytics): implement AnalyticsRepository_v2"
# Merge to main only after testing
git checkout main
git merge feature/v2-day1-analytics-repo
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Migration breaks existing features | Medium | High | Comprehensive testing, feature flags |
| Performance issues with local queries | Low | Medium | Indexed queries, profiling |
| Sync conflicts increase | Medium | Medium | Better conflict UI, documentation |
| Team velocity impact | Medium | Low | Clear tasks, pair programming |

---

## Post-Migration Monitoring

After V2 deployment, monitor:
- App crash rate
- API error rate (should decrease)
- Sync success rate
- User-reported issues
- App performance metrics

**Review Date:** January 16, 2026 (1 week post-launch)

---

## Questions & Blockers

Use this section to track blockers:

| Date | Issue | Owner | Status |
|------|-------|-------|--------|
| | | | |

---

**Last Updated:** January 2, 2026  
**Next Review:** Daily standup at 9:00 AM
