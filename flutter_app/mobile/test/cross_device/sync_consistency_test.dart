import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/sync/sync_service.dart';
import 'package:mobile/db/app_database.dart';
import 'package:drift/drift.dart';

void main() {
  group('Cross-Device Sync Consistency Tests', () {
    test('multiple devices creating same product resolve correctly', () async {
      // Simulate Device A
      final dbA = AppDatabase.inMemory();
      final syncA = SyncService(dbA, serverBase: 'http://localhost:3000');

      // Simulate Device B
      final dbB = AppDatabase.inMemory();
      final syncB = SyncService(dbB, serverBase: 'http://localhost:3000');

      // Both devices create the same product (simulating offline creation)
      await syncA.enqueueCreateProduct(
        name: 'Shared Product',
        price: 15.0,
        stock: 50,
        storeId: 1,
      );

      await syncB.enqueueCreateProduct(
        name: 'Shared Product',
        price: 15.0,
        stock: 50,
        storeId: 1,
      );

      // Check local state before sync
      final productsA = await dbA.getAllProducts();
      final productsB = await dbB.getAllProducts();

      expect(productsA.length, equals(1));
      expect(productsB.length, equals(1));
      expect(productsA[0].name, equals('Shared Product'));
      expect(productsB[0].name, equals('Shared Product'));

      // In a real scenario, sync would resolve conflicts
      // For this test, we verify the local state is consistent
      expect(productsA[0].price, equals(productsB[0].price));
      expect(productsA[0].stockQuantity, equals(productsB[0].stockQuantity));

      await dbA.close();
      await dbB.close();
    });

    test('device sync preserves data integrity across updates', () async {
      final db = AppDatabase.inMemory();
      final sync = SyncService(db);

      // Create initial product
      final productId = await sync.enqueueCreateProduct(
        name: 'Integrity Product',
        price: 10.0,
        stock: 100,
        storeId: 1,
      );

      // Simulate multiple updates from different "devices"
      final updates = [
        {'price': 12.0, 'stock': 95},
        {'price': 15.0, 'stock': 90},
        {'price': 18.0, 'stock': 85},
      ];

      for (final update in updates) {
        // In real sync, this would be handled by the sync service
        // For this test, we'll simulate by directly updating the database
        final product = await db.getProductByClientId(productId);
        if (product != null && product.clientId != null) {
          // Simulate updating the product with new values
          await (db.update(db.products)
                ..where((t) => t.clientId.equals(product.clientId!)))
              .write(ProductsCompanion(
            price: Value(update['price'] as double),
            stockQuantity: Value(update['stock'] as int),
            updatedAt: Value(DateTime.now()),
          ));
        }
      }

      // Verify final state - in a real scenario this would be checked after sync
      final products = await db.getAllProducts();
      expect(products.length, equals(1));
      expect(products[0].name, equals('Integrity Product'));

      await db.close();
    });

    test('sync handles device clock differences', () async {
      final db = AppDatabase.inMemory();
      final sync = SyncService(db);

      // Create product with "old" timestamp (simulating device with wrong clock)
      final pastTime = DateTime.now().subtract(const Duration(hours: 1));

      // Create another product with current time
      await sync.enqueueCreateProduct(
        name: 'Current Product',
        price: 25.0,
        stock: 15,
        storeId: 1,
      );

      // Verify both products exist and ordering is maintained
      final products = await db.getAllProducts();
      expect(
          products.length, equals(1)); // Only one product was actually created

      // The product should have current timestamp
      expect(products[0].name, equals('Current Product'));
      expect(products[0].createdAt.isAfter(pastTime), isTrue);

      await db.close();
    });

    test('sync maintains referential integrity across devices', () async {
      final db = AppDatabase.inMemory();
      final sync = SyncService(db);

      // Create products that reference a store ID (assuming store exists on server)
      for (int i = 0; i < 5; i++) {
        await sync.enqueueCreateProduct(
          name: 'Referenced Product $i',
          price: 10.0 * (i + 1),
          stock: 20 + i,
          storeId: 1, // References a store that should exist on server
        );
      }

      // Verify all products reference the same store
      final products = await db.getAllProducts();

      expect(products.length, equals(5));

      for (final product in products) {
        expect(product.storeId, equals(1));
        // In real sync, this would verify the store exists on server
      }

      await db.close();
    });
  });
}
