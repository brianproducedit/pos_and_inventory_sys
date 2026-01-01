import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/sync/sync_background.dart';

class _FakeDb {
  bool closed = false;
  Future<void> close() async {
    closed = true;
  }
}

class _FakeSyncService {
  bool syncPendingChangesBatchCalled = false;
  bool pullChangesSinceSeqCalled = false;

  Future<bool> syncPendingChangesBatch() async {
    syncPendingChangesBatchCalled = true;
    return true;
  }

  Future<void> pullChangesSinceSeq() async {
    pullChangesSinceSeqCalled = true;
  }
}

void main() {
  test(
      'runBackgroundTask uses sync service but does NOT close db (singleton pattern)',
      () async {
    final fakeDb = _FakeDb();
    final fakeService = _FakeSyncService();

    final result = await runBackgroundTask(
      openDb: () async => fakeDb,
      syncServiceFactory: (db) => fakeService,
    );

    expect(result, isTrue);
    expect(fakeService.syncPendingChangesBatchCalled, isTrue);
    expect(fakeService.pullChangesSinceSeqCalled, isTrue);
    // Database is NOT closed to avoid race conditions with foreground operations
    // The singleton pattern ensures the database stays open for the app lifecycle
    expect(fakeDb.closed, isFalse);
  });
}
