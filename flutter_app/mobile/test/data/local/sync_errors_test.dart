import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'package:mobile/data/repositories/sync_repository.dart';
import 'package:mobile/domain/models/sync_error.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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

  test('logSyncError creates row and getErrors returns it', () async {
    final db = DatabaseHelper();
    final d = await db.database;

    // Insert a fake queue item to reference
    final now = DateTime.now().millisecondsSinceEpoch;
    final pid = await d.insert('products', {
      'store_id': 1,
      'name': 'E1',
      'sku': 'E01',
      'price': 1.0,
      'stock_quantity': 1,
      'is_synced': 0,
      'last_updated': now
    });

    // simulate an error
    await db.logSyncError(
        queueId: 1, tableName: 'products', rowId: pid, error: 'boom');

    final repo = SyncRepository(db: db);
    final errors = await repo.getErrors();
    expect(errors, isNotEmpty);
    final e = errors.first as SyncError;
    expect(e.tableName, 'products');
    expect(e.error, contains('boom'));

    // clear it
    await repo.clearError(e.id!);
    final after = await repo.getErrors();
    expect(after, isEmpty);
  });
}
