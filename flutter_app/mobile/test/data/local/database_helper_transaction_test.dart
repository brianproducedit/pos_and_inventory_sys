import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/data/local/database_helper.dart';
import '../../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Initialize shared sqflite FFI bootstrap for tests
    initSqfliteForTests();
    await DatabaseHelper.initTestDb();
  });

  tearDown(() async {
    await DatabaseHelper.resetTestDb();
  });

  test('insertProduct rolls back when sync_queue insert fails', () async {
    final helper = DatabaseHelper();
    final db = await helper.database;

    // Install a trigger that forces an error on any insert into sync_queue
    await db.execute('''
      CREATE TRIGGER test_force_error BEFORE INSERT ON sync_queue
      BEGIN
        SELECT RAISE(ABORT, 'forced-error');
      END;
    ''');

    // Attempt to insert product — the trigger should abort the transaction
    expect(() async {
      await helper.insertProduct(name: 'p1', sku: 's1', price: 1.0);
    }, throwsA(isA<Exception>()));

    // Ensure no partial writes: products and sync_queue should be empty
    final products = await db.query('products');
    final queue = await db.query('sync_queue');
    expect(products, isEmpty);
    expect(queue, isEmpty);

    // Clean up trigger
    await db.execute('DROP TRIGGER IF EXISTS test_force_error');
  });

  test('updateStock rolls back when sync_queue insert fails', () async {
    final helper = DatabaseHelper();
    final db = await helper.database;

    // Insert a product successfully
    final id = await helper.insertProduct(name: 'p2', sku: 's2', price: 2.0);
    final rowsBefore =
        await db.query('products', where: 'id = ?', whereArgs: [id]);
    expect(rowsBefore.first['stock_quantity'], equals(0));

    // Install trigger to fail sync_queue inserts
    await db.execute('''
      CREATE TRIGGER test_force_error BEFORE INSERT ON sync_queue
      BEGIN
        SELECT RAISE(ABORT, 'forced-error');
      END;
    ''');

    // Try updateStock — should throw and rollback
    expect(() async {
      await helper.updateStock(id, 10);
    }, throwsA(isA<Exception>()));

    // Verify stock not updated
    final rowsAfter =
        await db.query('products', where: 'id = ?', whereArgs: [id]);
    expect(rowsAfter.first['stock_quantity'], equals(0));

    // Ensure no UPDATE queue entry was added (the original CREATE entry should still exist)
    final queue = await db.query('sync_queue');
    final updates = queue.where((r) => r['action'] == 'UPDATE').toList();
    expect(updates, isEmpty);

    // Clean up trigger
    await db.execute('DROP TRIGGER IF EXISTS test_force_error');
  });
}
