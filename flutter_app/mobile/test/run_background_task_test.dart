import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/sync/sync_background.dart';
import 'package:mobile/sync/sync_service.dart';
import 'test_helpers.dart';

class FakeDb {
  bool closed = false;
  Future<void> close() async {
    closed = true;
  }
}

class FakeSyncService {
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
  initializeTestHelpersOnce();

  test('runBackgroundTask uses injected factories and closes DB', () async {
    final fakeDb = FakeDb();

    Future<FakeDb> openDb() async => fakeDb;

    dynamic syncFactory(db) {
      // Return a fake service that exposes pushChanges and pullChanges
      return FakeSyncService();
    }

    final result = await runBackgroundTask(
      openDb: () async => fakeDb as dynamic,
      syncServiceFactory: (db) => FakeSyncService() as dynamic,
    );

    expect(result, isTrue);
    // close should have been called on the fake db
    expect((fakeDb as FakeDb).closed, isTrue);
  });

  test('runBackgroundTask returns false on sync exception', () async {
    final fakeDb = FakeDb();
    Future<FakeDb> openDb() async => fakeDb;
    dynamic syncFactory(db) => _BadSyncService();

    final result = await runBackgroundTask(
      openDb: () async => fakeDb as dynamic,
      syncServiceFactory: (db) => _BadSyncService() as dynamic,
    );

    expect(result, isFalse);
    expect((fakeDb as FakeDb).closed, isTrue);
  });

  test('runBackgroundTask prefers syncPendingChanges when available', () async {
    final fakeDb = FakeDb();
    Future<FakeDb> openDb() async => fakeDb;

    final service = _FullSyncService();

    final result = await runBackgroundTask(
      openDb: () async => fakeDb as dynamic,
      syncServiceFactory: (db) => service as dynamic,
    );

    expect(result, isTrue);
    expect(service.syncCalled, isTrue);
    expect(service.pullCalled, isTrue);
    expect((fakeDb as FakeDb).closed, isTrue);
  });
}

class _FullSyncService {
  bool syncCalled = false;
  bool pullCalled = false;

  Future<bool> syncPendingChanges() async {
    syncCalled = true;
    return true;
  }

  Future<void> pullChanges({required DateTime since}) async {
    pullCalled = true;
  }
}

class _BadSyncService {
  Future<void> pushChanges() async {
    throw Exception('boom');
  }

  Future<void> pullChanges({required DateTime since}) async {}
}
