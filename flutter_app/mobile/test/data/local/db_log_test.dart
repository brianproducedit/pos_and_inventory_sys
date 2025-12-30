import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/data/local/database_helper.dart';
import '../../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    initSqfliteForTests();
    await DatabaseHelper.initTestDb();
  });

  tearDown(() async {
    await DatabaseHelper.resetTestDb();
  });

  test('db logSyncError direct', () async {
    final db = DatabaseHelper();
    final d = await db.database;
    print('TEST2: db opened');

    final now = DateTime.now().millisecondsSinceEpoch;
    final pid = await d.insert('products', {
      'store_id': 1,
      'name': 'DBT',
      'sku': 'DBT01',
      'price': 1.0,
      'stock_quantity': 1,
      'is_synced': 0,
      'last_updated': now
    });
    print('TEST2: inserted product id=$pid');

    print('TEST2: calling logSyncError');
    await db.logSyncError(
        queueId: 1, tableName: 'products', rowId: pid, error: 'boom');
    print('TEST2: logSyncError completed');

    final errs = await d.query('sync_errors');
    print('TEST2: errors count=${errs.length}');
    expect(errs.length, greaterThanOrEqualTo(1));
  }, timeout: Timeout(Duration(seconds: 20)));
}
