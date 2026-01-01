import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Monitors network connectivity and provides real-time updates.
/// Performs actual internet connectivity checks (not just WiFi/cellular status).
class ConnectivityMonitor {
  static final ConnectivityMonitor _instance = ConnectivityMonitor._internal();
  factory ConnectivityMonitor() => _instance;
  ConnectivityMonitor._internal();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  bool _hasConnection = false;
  StreamSubscription<ConnectivityResult>? _subscription;

  /// Stream that emits connectivity status changes.
  Stream<bool> get onConnectivityChanged => _connectionController.stream;

  /// Current connectivity status (cached).
  bool get hasConnection => _hasConnection;

  /// Initialize the connectivity monitor.
  /// Should be called once during app startup.
  Future<void> initialize() async {
    // Check initial connectivity
    _hasConnection = await checkActualConnectivity();
    _connectionController.add(_hasConnection);

    // Listen for connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen((result) async {
      // ConnectivityResult can be misleading (shows WiFi but no internet)
      // Always verify with actual connectivity check
      final hasInternet = await checkActualConnectivity();

      if (hasInternet != _hasConnection) {
        _hasConnection = hasInternet;
        _connectionController.add(hasInternet);
        debugPrint(
            'ConnectivityMonitor: Connection ${hasInternet ? "restored" : "lost"}');
      }
    });
  }

  /// Perform actual internet connectivity check by attempting DNS lookup.
  /// This is more reliable than just checking WiFi/cellular status.
  Future<bool> checkActualConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on TimeoutException catch (_) {
      return false;
    } on SocketException catch (_) {
      return false;
    } catch (e) {
      debugPrint('ConnectivityMonitor: Unexpected error: $e');
      return false;
    }
  }

  /// Dispose resources. Call when app is closing.
  void dispose() {
    _subscription?.cancel();
    _connectionController.close();
  }
}
