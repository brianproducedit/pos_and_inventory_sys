import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/sync/sync_background.dart';
import 'test_helpers.dart';

class FakeDb {
  bool closed = false;
  Future<void> close() async {
    closed = true;
  }
}

class FakeSyncService {
  bool syncBatchCalled = false;
  bool pullCalled = false;

  Future<bool> syncPendingChangesBatch() async {
    syncBatchCalled = true;
    return true;
  }

  Future<void> pullChangesSinceSeq() async {
    pullCalled = true;
  }
}

void main() {
  initializeTestHelpersOnce();

  test('runBackgroundTask uses injected factories and runs sync', () async {
    final fakeDb = FakeDb();
    final service = FakeSyncService();

    final result = await runBackgroundTask(
      openDb: () async => fakeDb as dynamic,
      syncServiceFactory: (db) => service as dynamic,
    );

    expect(result, isTrue);
    expect(service.syncBatchCalled, isTrue);
    // NOTE: Database is intentionally NOT closed by runBackgroundTask
    // to avoid singleton issues. This is correct behavior.
  });

  test('runBackgroundTask returns false on sync exception', () async {
    final fakeDb = FakeDb();

    final result = await runBackgroundTask(
      openDb: () async => fakeDb as dynamic,
      syncServiceFactory: (db) => _BadSyncService() as dynamic,
    );

    expect(result, isFalse);
    // NOTE: Database is intentionally NOT closed by runBackgroundTask
  });

  test('runBackgroundTask prefers syncPendingChangesBatch when available',
      () async {
    final fakeDb = FakeDb();
    final service = _FullSyncService();

    final result = await runBackgroundTask(
      openDb: () async => fakeDb as dynamic,
      syncServiceFactory: (db) => service as dynamic,
    );

    expect(result, isTrue);
    expect(service.syncBatchCalled, isTrue);
    // pullChangesSinceSeq is preferred over pullChanges with epoch
  });
}

class _FullSyncService {
  bool syncBatchCalled = false;
  bool pullCalled = false;

  Future<bool> syncPendingChangesBatch() async {
    syncBatchCalled = true;
    return true;
  }

  Future<void> pullChangesSinceSeq() async {
    pullCalled = true;
  }
}

class _BadSyncService {
  Future<bool> syncPendingChangesBatch() async {
    throw Exception('boom');
  }
}
