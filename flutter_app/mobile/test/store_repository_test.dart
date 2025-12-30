import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mobile/data/local/database_helper.dart';
import 'package:mobile/data/repositories/store_repository.dart';
import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    initSqfliteForTests();
    await DatabaseHelper.initTestDb();
  });

  tearDown(() async {
    await DatabaseHelper.resetTestDb();
  });

  test('addStore writes store row and enqueues CREATE sync item', () async {
    final db = DatabaseHelper();
    final repo = StoreRepository(db: db);

    final id = await repo.addStore(name: 'Test Store', location: 'Test Loc');
    expect(id, greaterThan(0));

    final rows = await (await db.database)
        .query('stores', where: 'id = ?', whereArgs: [id]);
    expect(rows, isNotEmpty);
    expect(rows.first['name'], equals('Test Store'));

    final queue = await (await db.database).query('sync_queue',
        where: 'table_name = ? AND row_id = ?', whereArgs: ['stores', id]);
    expect(queue, isNotEmpty);
    expect(queue.first['action'], equals('CREATE'));
  });

  test('updateStore enqueues UPDATE', () async {
    final db = DatabaseHelper();
    final repo = StoreRepository(db: db);

    final id = await repo.addStore(name: 'S', location: null);
    final updated = await repo.updateStore(id, {'location': 'New L'});
    expect(updated, equals(1));

    final queue = await (await db.database).query('sync_queue',
        where: 'table_name = ? AND row_id = ? AND action = ?',
        whereArgs: ['stores', id, 'UPDATE']);
    expect(queue, isNotEmpty);
  });

  test('deleteStore enqueues DELETE and removes row', () async {
    final db = DatabaseHelper();
    final repo = StoreRepository(db: db);

    final id = await repo.addStore(name: 'ToDelete', location: null);
    final deleted = await repo.deleteStore(id);
    expect(deleted, equals(1));

    final rows = await (await db.database)
        .query('stores', where: 'id = ?', whereArgs: [id]);
    expect(rows, isEmpty);

    final queue = await (await db.database).query('sync_queue',
        where: 'table_name = ? AND row_id = ? AND action = ?',
        whereArgs: ['stores', id, 'DELETE']);
    expect(queue, isNotEmpty);
  });
}
