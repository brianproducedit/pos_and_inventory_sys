import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/data/local/database_helper.dart';
import '../../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initTestDb sets journal_mode without throwing', () async {
    // Initialize the shared test bootstrap (sqflite FFI + bindings)
    initSqfliteForTests();

    await DatabaseHelper.initTestDb();

    final db = DatabaseHelper.debugDb;
    expect(db, isNotNull);

    // Ensure we can query PRAGMA without raising
    final res = await db!.rawQuery('PRAGMA journal_mode');
    expect(res, isNotEmpty);

    // Ensure setting busy_timeout doesn't throw (some drivers require rawQuery)
    await db.rawQuery('PRAGMA busy_timeout = 5000');
    final bt = await db.rawQuery('PRAGMA busy_timeout');
    expect(bt, isNotNull);

    await DatabaseHelper.resetTestDb();
  });
}
