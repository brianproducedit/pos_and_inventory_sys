import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/sync/sync_background.dart';

class FakeServiceWithPull {
  bool syncCalled = false;
  DateTime? pulledSince;

  Future<bool> syncPendingChanges() async {
    syncCalled = true;
    return true;
  }

  Future<void> pullChanges({required DateTime since}) async {
    pulledSince = since;
    return;
  }
}

void main() {
  test('syncUsing calls pullChanges with epoch when available', () async {
    final svc = FakeServiceWithPull();

    final res = await syncUsing(svc);

    expect(res, isTrue);
    expect(svc.syncCalled, isTrue);
    expect(svc.pulledSince, isNotNull);
    expect(svc.pulledSince, equals(DateTime.fromMillisecondsSinceEpoch(0)));
  });
}
