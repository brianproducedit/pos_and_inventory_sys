import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/sync/sync_background.dart';

class FakeSyncService {
  bool pushCalled = false;
  bool pullCalled = false;

  Future<bool> syncPendingChangesBatch() async {
    pushCalled = true;
    return true;
  }

  Future<void> pullChangesSinceSeq() async {
    pullCalled = true;
  }
}

void main() {
  test('syncUsing calls push and pull', () async {
    final fake = FakeSyncService();
    final result = await syncUsing(fake);
    expect(result, isTrue);
    expect(fake.pushCalled, isTrue);
    expect(fake.pullCalled, isTrue);
  });

  test('syncUsing returns false on exception', () async {
    final bad = _BadService();
    final result = await syncUsing(bad);
    expect(result, isFalse);
  });
}

class _BadService {
  Future<void> pushChanges() async {
    throw Exception('boom');
  }

  Future<void> pullChanges({required DateTime since}) async {}
}
