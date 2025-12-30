import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'test_helpers.dart';
import 'package:mobile/data/repositories/product_repository.dart';
import 'package:mobile/domain/models/product.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProductRepository', () {
    late DatabaseHelper db;
    late ProductRepository repo;

    setUp(() async {
      initSqfliteForTests();
      await DatabaseHelper.initTestDb();
      db = DatabaseHelper();
      repo = ProductRepository(db: db, api: null as dynamic);
    });

    tearDown(() async {
      try {
        final d = await db.database;
        await d.delete('sync_queue');
        await d.delete('products');
        await DatabaseHelper.resetTestDb();
      } catch (_) {}
    });

    test('addProduct writes to products and enqueues sync item', () async {
      final p = Product(
          name: 'Test Widget', sku: 'TEST-001', price: 9.99, stockQuantity: 5);
      final id = await repo.addProduct(p);
      expect(id, greaterThan(0));

      final d = await db.database;
      final prods = await d.query('products', where: 'id = ?', whereArgs: [id]);
      expect(prods, isNotEmpty);

      final queue =
          await d.query('sync_queue', where: 'row_id = ?', whereArgs: [id]);
      expect(queue, isNotEmpty);
      final q = queue.first;
      expect(q['table_name'], equals('products'));
      expect(q['action'], equals('CREATE'));
    });
  });
}
