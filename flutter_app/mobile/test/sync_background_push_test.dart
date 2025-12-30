import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/sync/sync_background.dart';

class _FakeDb {
  bool closed = false;
  Future<void> close() async {
    closed = true;
  }
}

class _FakeSyncService {
  bool pushCalled = false;
  bool pullCalled = false;

  Future<void> pushChanges() async {
    pushCalled = true;
  }

  Future<void> pullChanges({required DateTime since}) async {
    pullCalled = true;
  }
}

void main() {
  test('runBackgroundTask uses sync service and closes db', () async {
    final fakeDb = _FakeDb();
    final fakeService = _FakeSyncService();

    final result = await runBackgroundTask(
      openDb: () async => fakeDb,
      syncServiceFactory: (db) => fakeService,
    );

    expect(result, isTrue);
    expect(fakeService.pushCalled, isTrue);
    expect(fakeService.pullCalled, isTrue);
    expect(fakeDb.closed, isTrue);
  });
}
