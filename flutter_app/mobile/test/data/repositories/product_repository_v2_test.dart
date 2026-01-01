import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import '../../../lib/db/app_database.dart';
import '../../../lib/data/repositories/product_repository_v2.dart';

void main() {
  late AppDatabase database;
  late ProductRepository productRepository;
  late int testStoreId;

  setUp(() async {
    // Create in-memory database for testing
    database = AppDatabase(NativeDatabase.memory());
    productRepository = ProductRepository(database);

    // Create a test store
    testStoreId = await database.into(database.stores).insert(
      StoresCompanion.insert(
        clientId: Value('test-store'),
        name: 'Test Store',
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('ProductRepository V2 - CRUD Operations', () {
    test('create should create product and enqueue sync', () async {
      final productId = await productRepository.create(
        name: 'Test Product',
        description: 'A test product',
        sku: 'TEST-001',
        price: 19.99,
        stockQuantity: 100,
        storeId: testStoreId,
      );

      expect(productId, greaterThan(0));

      // Verify product was created
      final product = await productRepository.getById(productId);
      expect(product, isNotNull);
      expect(product!.name, 'Test Product');
      expect(product.description, 'A test product');
      expect(product.sku, 'TEST-001');
      expect(product.price, 19.99);
      expect(product.stockQuantity, 100);
      expect(product.storeId, testStoreId);
      expect(product.syncStatus, SyncStatus.pending);
      expect(product.isActive, true);

      // Verify sync queue entry
      final syncItems = await (database.select(database.syncQueue)
            ..where((q) => q.resourceType.equals('product'))
            ..where((q) => q.resourceId.equals(productId)))
          .get();
      expect(syncItems.length, 1);
      expect(syncItems.first.operation, 'create');
      expect(syncItems.first.status, 'pending');
    });

    test('getById should return product by id', () async {
      final productId = await productRepository.create(
        name: 'Get By ID Product',
        price: 9.99,
        storeId: testStoreId,
      );

      final product = await productRepository.getById(productId);
      expect(product, isNotNull);
      expect(product!.id, productId);
      expect(product.name, 'Get By ID Product');
    });

    test('getById should return null for non-existent product', () async {
      final product = await productRepository.getById(99999);
      expect(product, isNull);
    });

    test('getBySku should return product by SKU', () async {
      await productRepository.create(
        name: 'SKU Product',
        sku: 'UNIQUE-SKU-001',
        price: 15.00,
        storeId: testStoreId,
      );

      final product = await productRepository.getBySku('UNIQUE-SKU-001');
      expect(product, isNotNull);
      expect(product!.sku, 'UNIQUE-SKU-001');
      expect(product.name, 'SKU Product');
    });

    test('getBySku should return null for non-existent SKU', () async {
      final product = await productRepository.getBySku('NON-EXISTENT');
      expect(product, isNull);
    });

    test('getAll should return all active products', () async {
      await productRepository.create(
        name: 'Product 1',
        price: 10.00,
        storeId: testStoreId,
      );

      await productRepository.create(
        name: 'Product 2',
        price: 20.00,
        storeId: testStoreId,
      );

      final products = await productRepository.getAll();
      expect(products.length, greaterThanOrEqualTo(2));
      expect(products.any((p) => p.name == 'Product 1'), true);
      expect(products.any((p) => p.name == 'Product 2'), true);
    });

    test('update should update product and enqueue sync', () async {
      final productId = await productRepository.create(
        name: 'Original Product',
        price: 10.00,
        storeId: testStoreId,
      );

      await productRepository.update(
        productId,
        name: 'Updated Product',
        price: 15.00,
        description: 'Updated description',
      );

      final product = await productRepository.getById(productId);
      expect(product!.name, 'Updated Product');
      expect(product.price, 15.00);
      expect(product.description, 'Updated description');
      expect(product.syncStatus, SyncStatus.pending);

      // Verify sync queue has update operation
      final syncItems = await (database.select(database.syncQueue)
            ..where((q) => q.resourceType.equals('product'))
            ..where((q) => q.resourceId.equals(productId))
            ..where((q) => q.operation.equals('update')))
          .get();
      expect(syncItems.length, greaterThanOrEqualTo(1));
    });

    test('delete should soft delete product and enqueue sync', () async {
      final productId = await productRepository.create(
        name: 'Delete Me',
        price: 10.00,
        storeId: testStoreId,
      );

      await productRepository.delete(productId);

      // Product should still exist but be inactive
      final product = await productRepository.getById(productId);
      expect(product!.isActive, false);
      expect(product.syncStatus, SyncStatus.pending);

      // Verify sync queue has delete operation
      final syncItems = await (database.select(database.syncQueue)
            ..where((q) => q.resourceType.equals('product'))
            ..where((q) => q.resourceId.equals(productId))
            ..where((q) => q.operation.equals('delete')))
          .get();
      expect(syncItems.length, greaterThanOrEqualTo(1));
    });
  });

  group('ProductRepository V2 - Stock Management', () {
    test('updateStock should update stock quantity and enqueue sync', () async {
      final productId = await productRepository.create(
        name: 'Stock Product',
        price: 10.00,
        stockQuantity: 50,
        storeId: testStoreId,
      );

      await productRepository.updateStock(productId, 75);

      final product = await productRepository.getById(productId);
      expect(product!.stockQuantity, 75);
      expect(product.syncStatus, SyncStatus.pending);
    });

    test('adjustStock should add to stock quantity', () async {
      final productId = await productRepository.create(
        name: 'Adjust Stock Product',
        price: 10.00,
        stockQuantity: 50,
        storeId: testStoreId,
      );

      await productRepository.adjustStock(productId, 25);

      final product = await productRepository.getById(productId);
      expect(product!.stockQuantity, 75);
    });

    test('adjustStock should subtract from stock quantity', () async {
      final productId = await productRepository.create(
        name: 'Reduce Stock Product',
        price: 10.00,
        stockQuantity: 50,
        storeId: testStoreId,
      );

      await productRepository.adjustStock(productId, -20);

      final product = await productRepository.getById(productId);
      expect(product!.stockQuantity, 30);
    });

    test('adjustStock should not allow negative stock', () async {
      final productId = await productRepository.create(
        name: 'Negative Stock Product',
        price: 10.00,
        stockQuantity: 10,
        storeId: testStoreId,
      );

      await productRepository.adjustStock(productId, -20);

      final product = await productRepository.getById(productId);
      expect(product!.stockQuantity, 0); // Should clamp to 0
    });

    test('getLowStock should return products below threshold', () async {
      await productRepository.create(
        name: 'Low Stock 1',
        price: 10.00,
        stockQuantity: 3,
        storeId: testStoreId,
      );

      await productRepository.create(
        name: 'Low Stock 2',
        price: 10.00,
        stockQuantity: 5,
        storeId: testStoreId,
      );

      await productRepository.create(
        name: 'High Stock',
        price: 10.00,
        stockQuantity: 100,
        storeId: testStoreId,
      );

      final lowStockProducts = await productRepository.getLowStock(threshold: 10);
      expect(lowStockProducts.length, greaterThanOrEqualTo(2));
      expect(lowStockProducts.every((p) => p.stockQuantity <= 10), true);
    });
  });

  group('ProductRepository V2 - Store Filtering', () {
    test('getByStore should return only products for specified store', () async {
      // Create second store
      final store2Id = await database.into(database.stores).insert(
        StoresCompanion.insert(
          clientId: Value('store2'),
          name: 'Store 2',
        ),
      );

      await productRepository.create(
        name: 'Store 1 Product',
        price: 10.00,
        storeId: testStoreId,
      );

      await productRepository.create(
        name: 'Store 2 Product',
        price: 20.00,
        storeId: store2Id,
      );

      final store1Products = await productRepository.getByStore(testStoreId);
      expect(store1Products.length, greaterThanOrEqualTo(1));
      expect(store1Products.every((p) => p.storeId == testStoreId), true);
      expect(store1Products.any((p) => p.name == 'Store 1 Product'), true);
    });
  });

  group('ProductRepository V2 - Search', () {
    test('search should find products by name', () async {
      await productRepository.create(
        name: 'Searchable Widget',
        price: 10.00,
        storeId: testStoreId,
      );

      await productRepository.create(
        name: 'Another Product',
        price: 20.00,
        storeId: testStoreId,
      );

      final results = await productRepository.search('Widget');
      expect(results.length, greaterThanOrEqualTo(1));
      expect(results.any((p) => p.name.contains('Widget')), true);
    });

    test('search should be case-insensitive', () async {
      await productRepository.create(
        name: 'CaseSensitive Product',
        price: 10.00,
        storeId: testStoreId,
      );

      final results = await productRepository.search('casesensitive');
      expect(results.length, greaterThanOrEqualTo(1));
    });

    test('search should find products by SKU', () async {
      await productRepository.create(
        name: 'SKU Search Product',
        sku: 'SEARCH-SKU-001',
        price: 10.00,
        storeId: testStoreId,
      );

      final results = await productRepository.search('SEARCH-SKU');
      expect(results.length, greaterThanOrEqualTo(1));
      expect(results.any((p) => p.sku?.contains('SEARCH-SKU') ?? false), true);
    });
  });

  group('ProductRepository V2 - Sync Status', () {
    test('getPendingSyncProducts should return products with pending sync', () async {
      await productRepository.create(
        name: 'Pending Product',
        price: 10.00,
        storeId: testStoreId,
      );

      final pendingProducts = await productRepository.getPendingSyncProducts();
      expect(pendingProducts.length, greaterThanOrEqualTo(1));
      expect(pendingProducts.every((p) => p.syncStatus == SyncStatus.pending), true);
    });

    test('markAsSynced should update sync status', () async {
      final productId = await productRepository.create(
        name: 'To Sync Product',
        price: 10.00,
        storeId: testStoreId,
      );

      await productRepository.markAsSynced(productId, serverId: 200);

      final product = await productRepository.getById(productId);
      expect(product!.syncStatus, SyncStatus.synced);
      expect(product.serverId, 200);
    });
  });

  group('ProductRepository V2 - Active/Inactive', () {
    test('deactivate should mark product as inactive', () async {
      final productId = await productRepository.create(
        name: 'Active Product',
        price: 10.00,
        storeId: testStoreId,
      );

      await productRepository.deactivate(productId);

      final product = await productRepository.getById(productId);
      expect(product!.isActive, false);
    });

    test('activate should mark product as active', () async {
      final productId = await productRepository.create(
        name: 'Inactive Product',
        price: 10.00,
        storeId: testStoreId,
      );

      await productRepository.deactivate(productId);
      await productRepository.activate(productId);

      final product = await productRepository.getById(productId);
      expect(product!.isActive, true);
    });

    test('getAll should only return active products by default', () async {
      await productRepository.create(
        name: 'Active Product',
        price: 10.00,
        storeId: testStoreId,
      );

      final inactiveId = await productRepository.create(
        name: 'Inactive Product',
        price: 10.00,
        storeId: testStoreId,
      );
      await productRepository.deactivate(inactiveId);

      final products = await productRepository.getAll();
      expect(products.every((p) => p.isActive), true);
    });
  });

  group('ProductRepository V2 - Error Handling', () {
    test('update should throw for non-existent product', () async {
      expect(
        () => productRepository.update(99999, name: 'Updated'),
        throwsA(isA<Exception>()),
      );
    });

    test('delete should throw for non-existent product', () async {
      expect(
        () => productRepository.delete(99999),
        throwsA(isA<Exception>()),
      );
    });

    test('updateStock should throw for non-existent product', () async {
      expect(
        () => productRepository.updateStock(99999, 50),
        throwsA(isA<Exception>()),
      );
    });
  });
}
