import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import '../../../lib/db/app_database.dart';
import '../../../lib/data/repositories/sale_repository_v2.dart';
import '../../../lib/data/repositories/product_repository_v2.dart';
import '../../../lib/data/repositories/user_repository_v2.dart';

void main() {
  late AppDatabase database;
  late SaleRepository saleRepository;
  late ProductRepository productRepository;
  late UserRepository userRepository;
  late int testStoreId;
  late int testUserId;
  late int testProductId;

  setUp(() async {
    // Create in-memory database for testing
    database = AppDatabase(NativeDatabase.memory());
    saleRepository = SaleRepository(database);
    productRepository = ProductRepository(database);
    userRepository = UserRepository(database);

    // Create test store
    testStoreId = await database.into(database.stores).insert(
      StoresCompanion.insert(
        clientId: Value('test-store'),
        name: 'Test Store',
      ),
    );

    // Create test user
    testUserId = await userRepository.create(
      username: 'testcashier',
      password: 'Test123!',
      fullName: 'Test Cashier',
      role: UserRole.cashier,
      storeId: testStoreId,
    );

    // Create test product with stock
    testProductId = await productRepository.create(
      name: 'Test Product',
      price: 10.00,
      stockQuantity: 100,
      storeId: testStoreId,
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('SaleRepository V2 - Create Sale', () {
    test('createSale should create sale with items and deduct stock', () async {
      final saleItems = [
        SaleItemData(
          productId: testProductId,
          productName: 'Test Product',
          quantity: 5,
          unitPrice: 10.00,
          subtotal: 50.00,
        ),
      ];

      final saleId = await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 50.00,
        paymentMethod: 'cash',
      );

      expect(saleId, greaterThan(0));

      // Verify sale was created
      final sale = await saleRepository.getById(saleId);
      expect(sale, isNotNull);
      expect(sale!.userId, testUserId);
      expect(sale.storeId, testStoreId);
      expect(sale.totalAmount, 50.00);
      expect(sale.paymentMethod, 'cash');
      expect(sale.syncStatus, SyncStatus.pending);

      // Verify sale items
      final items = await (database.select(database.saleItems)
            ..where((si) => si.saleId.equals(saleId)))
          .get();
      expect(items.length, 1);
      expect(items.first.productId, testProductId);
      expect(items.first.quantity, 5);
      expect(items.first.unitPrice, 10.00);

      // Verify stock was deducted
      final product = await productRepository.getById(testProductId);
      expect(product!.stockQuantity, 95); // 100 - 5

      // Verify sync queue entry
      final syncItems = await (database.select(database.syncQueue)
            ..where((q) => q.resourceType.equals('sale'))
            ..where((q) => q.resourceId.equals(saleId)))
          .get();
      expect(syncItems.length, 1);
      expect(syncItems.first.operation, 'create');
    });

    test('createSale should handle multiple items', () async {
      // Create second product
      final product2Id = await productRepository.create(
        name: 'Product 2',
        price: 20.00,
        stockQuantity: 50,
        storeId: testStoreId,
      );

      final saleItems = [
        SaleItemData(
          productId: testProductId,
          productName: 'Test Product',
          quantity: 3,
          unitPrice: 10.00,
          subtotal: 30.00,
        ),
        SaleItemData(
          productId: product2Id,
          productName: 'Product 2',
          quantity: 2,
          unitPrice: 20.00,
          subtotal: 40.00,
        ),
      ];

      final saleId = await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 70.00,
        paymentMethod: 'card',
      );

      // Verify sale items
      final items = await (database.select(database.saleItems)
            ..where((si) => si.saleId.equals(saleId)))
          .get();
      expect(items.length, 2);

      // Verify stock deductions
      final product1 = await productRepository.getById(testProductId);
      expect(product1!.stockQuantity, 97); // 100 - 3

      final product2 = await productRepository.getById(product2Id);
      expect(product2!.stockQuantity, 48); // 50 - 2
    });

    test('createSale should throw if stock is insufficient', () async {
      final saleItems = [
        SaleItemData(
          productId: testProductId,
          productName: 'Test Product',
          quantity: 150, // More than available (100)
          unitPrice: 10.00,
          subtotal: 1500.00,
        ),
      ];

      expect(
        () => saleRepository.createSale(
          userId: testUserId,
          storeId: testStoreId,
          items: saleItems,
          totalAmount: 1500.00,
          paymentMethod: 'cash',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('createSale should generate unique transaction number', () async {
      final saleItems = [
        SaleItemData(
          productId: testProductId,
          productName: 'Test Product',
          quantity: 1,
          unitPrice: 10.00,
          subtotal: 10.00,
        ),
      ];

      final sale1Id = await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      final sale2Id = await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      final sale1 = await saleRepository.getById(sale1Id);
      final sale2 = await saleRepository.getById(sale2Id);

      expect(sale1!.transactionNumber, isNotEmpty);
      expect(sale2!.transactionNumber, isNotEmpty);
      expect(sale1.transactionNumber, isNot(sale2.transactionNumber));
    });
  });

  group('SaleRepository V2 - Retrieve Sales', () {
    test('getById should return sale with items', () async {
      final saleItems = [
        SaleItemData(
          productId: testProductId,
          productName: 'Test Product',
          quantity: 2,
          unitPrice: 10.00,
          subtotal: 20.00,
        ),
      ];

      final saleId = await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 20.00,
        paymentMethod: 'cash',
      );

      final sale = await saleRepository.getById(saleId);
      expect(sale, isNotNull);
      expect(sale!.id, saleId);
    });

    test('getById should return null for non-existent sale', () async {
      final sale = await saleRepository.getById(99999);
      expect(sale, isNull);
    });

    test('getAll should return all sales', () async {
      final saleItems = [
        SaleItemData(
          productId: testProductId,
          productName: 'Test Product',
          quantity: 1,
          unitPrice: 10.00,
          subtotal: 10.00,
        ),
      ];

      await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 10.00,
        paymentMethod: 'card',
      );

      final sales = await saleRepository.getAll();
      expect(sales.length, greaterThanOrEqualTo(2));
    });

    test('getByStore should return only sales for specified store', () async {
      // Create second store
      final store2Id = await database.into(database.stores).insert(
        StoresCompanion.insert(
          clientId: Value('store2'),
          name: 'Store 2',
        ),
      );

      final saleItems = [
        SaleItemData(
          productId: testProductId,
          productName: 'Test Product',
          quantity: 1,
          unitPrice: 10.00,
          subtotal: 10.00,
        ),
      ];

      await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      await saleRepository.createSale(
        userId: testUserId,
        storeId: store2Id,
        items: saleItems,
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      final store1Sales = await saleRepository.getByStore(testStoreId);
      expect(store1Sales.every((s) => s.storeId == testStoreId), true);
    });

    test('getByUser should return only sales by specified user', () async {
      // Create second user
      final user2Id = await userRepository.create(
        username: 'cashier2',
        password: 'Test123!',
        fullName: 'Cashier 2',
        role: UserRole.cashier,
        storeId: testStoreId,
      );

      final saleItems = [
        SaleItemData(
          productId: testProductId,
          productName: 'Test Product',
          quantity: 1,
          unitPrice: 10.00,
          subtotal: 10.00,
        ),
      ];

      await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      await saleRepository.createSale(
        userId: user2Id,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      final user1Sales = await saleRepository.getByUser(testUserId);
      expect(user1Sales.every((s) => s.userId == testUserId), true);
    });

    test('getByDateRange should return sales within date range', () async {
      final saleItems = [
        SaleItemData(
          productId: testProductId,
          productName: 'Test Product',
          quantity: 1,
          unitPrice: 10.00,
          subtotal: 10.00,
        ),
      ];

      final saleId = await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      final now = DateTime.now();
      final startDate = now.subtract(Duration(hours: 1));
      final endDate = now.add(Duration(hours: 1));

      final sales = await saleRepository.getByDateRange(startDate, endDate);
      expect(sales.any((s) => s.id == saleId), true);
    });
  });

  group('SaleRepository V2 - Sync Status', () {
    test('getPendingSyncSales should return sales with pending sync', () async {
      final saleItems = [
        SaleItemData(
          productId: testProductId,
          productName: 'Test Product',
          quantity: 1,
          unitPrice: 10.00,
          subtotal: 10.00,
        ),
      ];

      await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      final pendingSales = await saleRepository.getPendingSyncSales();
      expect(pendingSales.length, greaterThanOrEqualTo(1));
      expect(pendingSales.every((s) => s.syncStatus == SyncStatus.pending), true);
    });

    test('markAsSynced should update sync status', () async {
      final saleItems = [
        SaleItemData(
          productId: testProductId,
          productName: 'Test Product',
          quantity: 1,
          unitPrice: 10.00,
          subtotal: 10.00,
        ),
      ];

      final saleId = await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      await saleRepository.markAsSynced(saleId, serverId: 300);

      final sale = await saleRepository.getById(saleId);
      expect(sale!.syncStatus, SyncStatus.synced);
      expect(sale.serverId, 300);
    });
  });

  group('SaleRepository V2 - Analytics', () {
    test('getTotalRevenue should calculate total from sales', () async {
      final saleItems = [
        SaleItemData(
          productId: testProductId,
          productName: 'Test Product',
          quantity: 1,
          unitPrice: 10.00,
          subtotal: 10.00,
        ),
      ];

      await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 20.00,
        paymentMethod: 'card',
      );

      final revenue = await saleRepository.getTotalRevenue();
      expect(revenue, greaterThanOrEqualTo(30.00));
    });

    test('getSalesCount should return number of sales', () async {
      final initialCount = await saleRepository.getSalesCount();

      final saleItems = [
        SaleItemData(
          productId: testProductId,
          productName: 'Test Product',
          quantity: 1,
          unitPrice: 10.00,
          subtotal: 10.00,
        ),
      ];

      await saleRepository.createSale(
        userId: testUserId,
        storeId: testStoreId,
        items: saleItems,
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      final newCount = await saleRepository.getSalesCount();
      expect(newCount, initialCount + 1);
    });
  });

  group('SaleRepository V2 - Transaction Integrity', () {
    test('failed sale creation should rollback stock deductions', () async {
      final initialStock = (await productRepository.getById(testProductId))!.stockQuantity;

      // Try to create sale with invalid data that will fail
      try {
        await saleRepository.createSale(
          userId: 99999, // Non-existent user
          storeId: testStoreId,
          items: [
            SaleItemData(
              productId: testProductId,
              productName: 'Test Product',
              quantity: 10,
              unitPrice: 10.00,
              subtotal: 100.00,
            ),
          ],
          totalAmount: 100.00,
          paymentMethod: 'cash',
        );
      } catch (e) {
        // Expected to fail
      }

      // Stock should remain unchanged
      final finalStock = (await productRepository.getById(testProductId))!.stockQuantity;
      expect(finalStock, initialStock);
    });
  });
}
