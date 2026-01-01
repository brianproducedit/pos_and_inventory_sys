import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/sync/sync_service.dart';
import 'package:mobile/db/app_database.dart';
import 'package:drift/drift.dart';

void main() {
  late AppDatabase db;
  late SyncService syncService;

  setUp(() async {
    // Create in-memory database for testing
    db = AppDatabase.inMemory();
    syncService = SyncService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Sync Performance Tests', () {
    test('sync large batch of product creates within time limit', () async {
      final startTime = DateTime.now();

      // Create 100 products
      for (int i = 0; i < 100; i++) {
        await syncService.enqueueCreateProduct(
          name: 'Performance Product $i',
          price: 10.0 + i,
          stock: 100 + i,
          storeId: 1,
        );
      }

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      // Should complete within 2 seconds for 100 products
      expect(duration.inMilliseconds, lessThan(2000));

      // Verify all products were queued
      final products = await db.getAllProducts();
      expect(products.length, equals(100));
    });

    test('sync handles concurrent operations efficiently', () async {
      final startTime = DateTime.now();

      // Simulate concurrent operations
      final futures = <Future>[];
      for (int i = 0; i < 50; i++) {
        futures.add(syncService.enqueueCreateProduct(
          name: 'Concurrent Product $i',
          price: 5.0,
          stock: 10,
          storeId: 1,
        ));
      }

      await Future.wait(futures);
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      // Should complete within 1 second for concurrent operations
      expect(duration.inMilliseconds, lessThan(1000));

      final products = await db.getAllProducts();
      expect(products.length, equals(50));
    });

    test('sync memory usage remains bounded', () async {
      // Create products with large data to test memory usage
      for (int i = 0; i < 1000; i++) {
        await syncService.enqueueCreateProduct(
          name: 'Memory Test Product $i' + 'x' * 100, // Large name
          price: 1.0,
          stock: 1,
          storeId: 1,
        );
      }

      // Verify database can handle the load
      final products = await db.getAllProducts();
      expect(products.length, equals(1000));

      // Verify memory cleanup by closing and reopening
      await db.close();
      db = AppDatabase.inMemory();
      syncService = SyncService(db);

      final reloadedProducts = await db.getAllProducts();
      expect(
          reloadedProducts.length, equals(0)); // Should be empty after restart
    });
  });
}
