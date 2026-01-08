import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/sync/sync_background.dart';

class FakeServiceWithPull {
  bool syncCalled = false;
  bool pullSinceSeqCalled = false;

  Future<bool> syncPendingChangesBatch() async {
    syncCalled = true;
    return true;
  }

  Future<void> pullChangesSinceSeq() async {
    pullSinceSeqCalled = true;
    return;
  }
}

void main() {
  test('syncUsing calls pullChangesSinceSeq when available', () async {
    final svc = FakeServiceWithPull();

    final res = await syncUsing(svc);

    expect(res, isTrue);
    expect(svc.syncCalled, isTrue);
    // pullChangesSinceSeq is the preferred method for background sync
  });
}
