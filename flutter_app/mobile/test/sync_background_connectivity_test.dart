import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/sync/sync_background.dart';

class FakeConnectivity implements Connectivity {
  final StreamController<ConnectivityResult> _controller =
      StreamController<ConnectivityResult>.broadcast();

  @override
  Future<ConnectivityResult> checkConnectivity() async =>
      ConnectivityResult.none;

  @override
  Stream<ConnectivityResult> get onConnectivityChanged => _controller.stream;

  // Helper to push events
  void push(ConnectivityResult r) => _controller.add(r);

  // Unused/unsupported members can be left unimplemented for tests
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registerConnectivityListener triggers onConnected callback when online',
      () async {
    final fake = FakeConnectivity();
    var called = false;

    final sub = registerConnectivityListener(fake, onConnected: () async {
      called = true;
    });

    // Simulate connectivity regained
    fake.push(ConnectivityResult.wifi);

    // Give event loop a moment
    await Future.delayed(Duration(milliseconds: 50));

    expect(called, isTrue);

    await sub.cancel();
  });
}
