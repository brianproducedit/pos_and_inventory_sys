import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/domain/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'test_helpers.dart';
import 'package:mobile/data/repositories/product_repository.dart';

void main() {
  initSqfliteForTests();

  group('ProductRepository update/delete', () {
    late DatabaseHelper db;
    late ProductRepository repo;

    setUp(() async {
      await DatabaseHelper.initTestDb();
      db = DatabaseHelper();
      repo = ProductRepository(db: db, api: null);
    });

    tearDown(() async {
      await DatabaseHelper.resetTestDb();
    });

    test('updateProduct updates row and enqueues update', () async {
      // Create a product row directly using the db helper for deterministic setup
      final dbClient = await db.database;
      final inserted = await dbClient.insert('products',
          {'name': 'ToUpdate', 'sku': 'U1', 'price': 5.0, 'stock_quantity': 3});

      final updated = await repo.updateProduct(inserted, {'price': 7.0});
      expect(updated, greaterThan(0));

      final rows = await dbClient
          .query('products', where: 'id = ?', whereArgs: [inserted]);
      expect(rows.first['price'], equals(7.0));

      final queue = await dbClient.query('sync_queue',
          where: 'row_id = ? AND action = ?', whereArgs: [inserted, 'UPDATE']);
      expect(queue, isNotEmpty);
    });

    test('deleteProduct deletes row and enqueues delete', () async {
      final dbClient = await db.database;
      final inserted = await dbClient.insert('products',
          {'name': 'ToDelete', 'sku': 'D1', 'price': 5.0, 'stock_quantity': 3});

      final deleted = await repo.deleteProduct(inserted);
      expect(deleted, greaterThan(0));

      final rows = await dbClient
          .query('products', where: 'id = ?', whereArgs: [inserted]);
      expect(rows, isEmpty);

      final queue = await dbClient.query('sync_queue',
          where: 'row_id = ? AND action = ?', whereArgs: [inserted, 'DELETE']);
      expect(queue, isNotEmpty);
    });
  });
}
