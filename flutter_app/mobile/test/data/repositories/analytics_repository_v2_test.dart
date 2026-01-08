import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/db/app_database.dart';
import 'package:mobile/data/repositories/analytics_repository_v2.dart' as v2;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late v2.AnalyticsRepository analyticsRepo;

  setUp(() {
    // Create in-memory database for testing
    db = AppDatabase.inMemory();
    analyticsRepo = v2.AnalyticsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('AnalyticsRepository getSalesSummary', () {
    test('returns empty summary when no sales exist', () async {
      final summary = await analyticsRepo.getSalesSummary();

      expect(summary.totalSales, 0);
      expect(summary.totalRevenue, 0.0);
      expect(summary.averageOrderValue, 0.0);
      expect(summary.cashSales, 0);
      expect(summary.cardSales, 0);
      expect(summary.mobileSales, 0);
    });

    test('calculates summary correctly with multiple sales', () async {
      // Create test store
      final storeId = await db.into(db.stores).insert(StoresCompanion.insert(
            name: 'Test Store',
            location: const Value('123 Test St'),
          ));

      // Create a test user (required for sales)
      final userId = await db.into(db.users).insert(UsersCompanion.insert(
            username: 'testuser',
            passwordHash: 'hash123',
            role: UserRole.cashier,
          ));

      // Create test sales
      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-001',
            userId: userId,
            storeId: storeId,
            totalAmount: 100.0,
            paymentMethod: 'cash',
          ));

      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-002',
            userId: userId,
            storeId: storeId,
            totalAmount: 200.0,
            paymentMethod: 'card',
          ));

      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-003',
            userId: userId,
            storeId: storeId,
            totalAmount: 150.0,
            paymentMethod: 'mobile',
          ));

      final summary = await analyticsRepo.getSalesSummary(storeId: storeId);

      expect(summary.totalSales, 3);
      expect(summary.totalRevenue, 450.0);
      expect(summary.averageOrderValue, 150.0);
      expect(summary.cashSales, 1);
      expect(summary.cardSales, 1);
      expect(summary.mobileSales, 1);
    });

    test('filters by date range correctly', () async {
      final storeId = await db.into(db.stores).insert(StoresCompanion.insert(
            name: 'Test Store',
            location: const Value('123 Test St'),
          ));

      final userId = await db.into(db.users).insert(UsersCompanion.insert(
            username: 'testuser',
            passwordHash: 'hash123',
            role: UserRole.cashier,
          ));

      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final twoDaysAgo = now.subtract(const Duration(days: 2));

      // Sale from 2 days ago
      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-OLD',
            userId: userId,
            storeId: storeId,
            totalAmount: 100.0,
            paymentMethod: 'cash',
            createdAt: Value(twoDaysAgo),
          ));

      // Sale from yesterday
      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-YESTERDAY',
            userId: userId,
            storeId: storeId,
            totalAmount: 200.0,
            paymentMethod: 'card',
            createdAt: Value(yesterday),
          ));

      // Get only yesterday's sales
      final summary = await analyticsRepo.getSalesSummary(
        storeId: storeId,
        startDate: yesterday.subtract(const Duration(hours: 1)),
        endDate: now,
      );

      expect(summary.totalSales, 1);
      expect(summary.totalRevenue, 200.0);
    });
  });

  group('AnalyticsRepository getTopProducts', () {
    test('returns top products sorted by quantity', () async {
      // Create store
      final storeId = await db.into(db.stores).insert(StoresCompanion.insert(
            name: 'Test Store',
            location: const Value('123 Test St'),
          ));

      final userId = await db.into(db.users).insert(UsersCompanion.insert(
            username: 'testuser',
            passwordHash: 'hash123',
            role: UserRole.cashier,
          ));

      // Create products
      final productId1 =
          await db.into(db.products).insert(ProductsCompanion.insert(
                name: 'Product 1',
                storeId: storeId,
                price: const Value(10.0),
                stockQuantity: const Value(100),
              ));

      final productId2 =
          await db.into(db.products).insert(ProductsCompanion.insert(
                name: 'Product 2',
                storeId: storeId,
                price: const Value(20.0),
                stockQuantity: const Value(100),
              ));

      // Create sale
      final saleId = await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-001',
            userId: userId,
            storeId: storeId,
            totalAmount: 100.0,
            paymentMethod: 'cash',
          ));

      // Create sale items
      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId1,
            quantity: 5,
            unitPrice: 10.0,
            totalPrice: 50.0,
          ));

      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId2,
            quantity: 2,
            unitPrice: 20.0,
            totalPrice: 40.0,
          ));

      final topProducts = await analyticsRepo.getTopProducts(
        storeId: storeId,
        limit: 10,
      );

      expect(topProducts.length, 2);
      expect(topProducts[0].productName, 'Product 1');
      expect(topProducts[0].quantitySold, 5);
      expect(topProducts[1].productName, 'Product 2');
      expect(topProducts[1].quantitySold, 2);
    });
  });

  group('AnalyticsRepository getSalesByPeriod', () {
    test('groups sales by day correctly', () async {
      final storeId = await db.into(db.stores).insert(StoresCompanion.insert(
            name: 'Test Store',
            location: const Value('123 Test St'),
          ));

      final userId = await db.into(db.users).insert(UsersCompanion.insert(
            username: 'testuser',
            passwordHash: 'hash123',
            role: UserRole.cashier,
          ));

      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));

      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-TODAY-1',
            userId: userId,
            storeId: storeId,
            totalAmount: 100.0,
            paymentMethod: 'cash',
            createdAt: Value(today),
          ));

      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-TODAY-2',
            userId: userId,
            storeId: storeId,
            totalAmount: 150.0,
            paymentMethod: 'card',
            createdAt: Value(today),
          ));

      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-YESTERDAY',
            userId: userId,
            storeId: storeId,
            totalAmount: 200.0,
            paymentMethod: 'mobile',
            createdAt: Value(yesterday),
          ));

      final periods = await analyticsRepo.getSalesByPeriod(
        storeId: storeId,
        granularity: 'day',
      );

      expect(periods.length, 2);
      expect(periods.any((p) => p.count == 2 && p.revenue == 250.0), true);
      expect(periods.any((p) => p.count == 1 && p.revenue == 200.0), true);
    });
  });

  group('AnalyticsRepository getLowStockProducts', () {
    test('returns products below threshold', () async {
      final storeId = await db.into(db.stores).insert(StoresCompanion.insert(
            name: 'Test Store',
            location: const Value('123 Test St'),
          ));

      await db.into(db.products).insert(ProductsCompanion.insert(
            name: 'Low Stock Product',
            storeId: storeId,
            price: const Value(10.0),
            stockQuantity: const Value(5),
          ));

      await db.into(db.products).insert(ProductsCompanion.insert(
            name: 'Normal Stock Product',
            storeId: storeId,
            price: const Value(20.0),
            stockQuantity: const Value(50),
          ));

      final lowStockProducts = await analyticsRepo.getLowStockProducts(
        storeId: storeId,
        threshold: 10,
      );

      expect(lowStockProducts.length, 1);
      expect(lowStockProducts[0].name, 'Low Stock Product');
      expect(lowStockProducts[0].stockQuantity, 5);
    });
  });

  group('AnalyticsRepository getPaymentMethodBreakdown', () {
    test('returns correct payment method distribution', () async {
      final storeId = await db.into(db.stores).insert(StoresCompanion.insert(
            name: 'Test Store',
            location: const Value('123 Test St'),
          ));

      final userId = await db.into(db.users).insert(UsersCompanion.insert(
            username: 'testuser',
            passwordHash: 'hash123',
            role: UserRole.cashier,
          ));

      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-CASH-1',
            userId: userId,
            storeId: storeId,
            totalAmount: 100.0,
            paymentMethod: 'cash',
          ));

      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-CASH-2',
            userId: userId,
            storeId: storeId,
            totalAmount: 200.0,
            paymentMethod: 'cash',
          ));

      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-CARD-1',
            userId: userId,
            storeId: storeId,
            totalAmount: 300.0,
            paymentMethod: 'card',
          ));

      final breakdown = await analyticsRepo.getPaymentMethodBreakdown(
        storeId: storeId,
      );

      expect(breakdown['cash'], 2);
      expect(breakdown['card'], 1);
    });
  });

  group('AnalyticsRepository getStoreComparison', () {
    test('compares performance across multiple stores', () async {
      // Create two stores
      final store1Id = await db.into(db.stores).insert(StoresCompanion.insert(
            name: 'Store 1',
            location: const Value('123 Test St'),
          ));

      final store2Id = await db.into(db.stores).insert(StoresCompanion.insert(
            name: 'Store 2',
            location: const Value('456 Test Ave'),
          ));

      final userId = await db.into(db.users).insert(UsersCompanion.insert(
            username: 'testuser',
            passwordHash: 'hash123',
            role: UserRole.cashier,
          ));

      // Add sales to store 1
      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-STORE1',
            userId: userId,
            storeId: store1Id,
            totalAmount: 100.0,
            paymentMethod: 'cash',
          ));

      // Add sales to store 2
      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-STORE2-1',
            userId: userId,
            storeId: store2Id,
            totalAmount: 200.0,
            paymentMethod: 'card',
          ));

      await db.into(db.sales).insert(SalesCompanion.insert(
            transactionNumber: 'TXN-STORE2-2',
            userId: userId,
            storeId: store2Id,
            totalAmount: 300.0,
            paymentMethod: 'mobile',
          ));

      final comparison = await analyticsRepo.getStoreComparison();

      expect(comparison.length, 2);
      // Store 2 should be first (higher revenue)
      expect(comparison[0].storeName, 'Store 2');
      expect(comparison[0].totalRevenue, 500.0);
      expect(comparison[1].storeName, 'Store 1');
      expect(comparison[1].totalRevenue, 100.0);
    });
  });
}
