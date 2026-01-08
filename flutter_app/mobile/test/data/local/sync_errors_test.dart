import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:mobile/db/app_database.dart';
import 'package:mobile/data/sync/sync_database_helper.dart';
import 'package:mobile/data/repositories/sync_repository.dart';

late AppDatabase testDb;
late SyncDatabaseHelper syncHelper;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    testDb = AppDatabase.inMemory();
    syncHelper = SyncDatabaseHelper(testDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  test('logSyncError creates row and getErrors returns it', () async {
    // Insert a sync queue item with an error
    await testDb.into(testDb.syncQueue).insert(SyncQueueCompanion.insert(
          resourceType: 'product',
          operation: 'CREATE',
          payloadJson: '{}',
          errorMessage: const Value('boom'),
        ));

    final repo = SyncRepository(dbHelper: syncHelper);
    final errors = await repo.getErrors();
    expect(errors, isNotEmpty);
    final e = errors.first;
    expect(e.tableName, 'products');
    expect(e.error, contains('boom'));

    // clear it
    await repo.clearError(e.id!);
    final after = await repo.getErrors();
    expect(after, isEmpty);
  });
}
