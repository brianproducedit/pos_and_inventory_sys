import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Monitors network connectivity and provides real-time updates.
/// Performs actual internet connectivity checks (not just WiFi/cellular status).
class ConnectivityMonitor {
  /// Set to true to force offline mode for testing (debug builds only)
  static bool forceOfflineForTesting = false;
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
    try {
      // Check initial connectivity
      _hasConnection = await checkActualConnectivity();
      _connectionController.add(_hasConnection);

      // Listen for connectivity changes
      _subscription =
          _connectivity.onConnectivityChanged.listen((result) async {
        // ConnectivityResult can be misleading (shows WiFi but no internet)
        // Always verify with actual connectivity check
        try {
          final hasInternet = await checkActualConnectivity();

          if (hasInternet != _hasConnection) {
            _hasConnection = hasInternet;
            _connectionController.add(hasInternet);
            debugPrint(
                'ConnectivityMonitor: Connection ${hasInternet ? "restored" : "lost"}');
          }
        } catch (e) {
          debugPrint(
              'ConnectivityMonitor: Error checking connectivity on change: $e');
          // Assume offline on error
          if (_hasConnection) {
            _hasConnection = false;
            _connectionController.add(false);
          }
        }
      });
    } catch (e) {
      debugPrint('ConnectivityMonitor: Error during initialization: $e');
      // Default to offline state on initialization error
      _hasConnection = false;
      _connectionController.add(false);
    }
  }

  /// Perform actual internet connectivity check by attempting DNS lookup.
  /// This is more reliable than just checking WiFi/cellular status.
  Future<bool> checkActualConnectivity() async {
    // Allow forcing offline mode for testing in debug builds
    if (kDebugMode && forceOfflineForTesting) {
      debugPrint('ConnectivityMonitor: FORCED OFFLINE MODE (testing)');
      return false;
    }

    try {
      // Try to reach the actual backend server first
      // Extract host from BASE_URL (e.g., "http://localhost:8000" -> "localhost")
      final backendHost = _extractHost();

      debugPrint('ConnectivityMonitor: Checking backend at $backendHost...');
      final result = await InternetAddress.lookup(backendHost)
          .timeout(const Duration(seconds: 5));
      final hasInternet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;

      if (hasInternet) {
        debugPrint('✅ ConnectivityMonitor: Backend reachable at $backendHost');
      } else {
        debugPrint(
            '❌ ConnectivityMonitor: Backend not reachable at $backendHost');
      }

      return hasInternet;
    } on TimeoutException catch (_) {
      debugPrint('⏱️ ConnectivityMonitor: Timeout - backend not reachable');
      return false;
    } on SocketException catch (e) {
      debugPrint(
          '🔌 ConnectivityMonitor: SocketException - backend not reachable: $e');

      // Fallback: Check general internet with google.com
      try {
        debugPrint('🌐 Fallback: Checking general internet connectivity...');
        final fallbackResult = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 3));
        final hasInternet = fallbackResult.isNotEmpty &&
            fallbackResult[0].rawAddress.isNotEmpty;

        if (hasInternet) {
          debugPrint(
              '⚠️ Internet available but backend not reachable - treating as OFFLINE for sync');
        }

        // Return false even if internet exists, because backend is unreachable
        return false;
      } catch (e) {
        debugPrint('❌ No internet at all');
        return false;
      }
    } on OSError catch (e) {
      debugPrint('ConnectivityMonitor: OSError - no internet: $e');
      return false;
    } catch (e) {
      debugPrint(
          'ConnectivityMonitor: Unexpected error (treating as offline): $e');
      return false;
    }
  }

  /// Extract hostname from BASE_URL for connectivity checking
  String _extractHost() {
    try {
      // Try to import and use Env, but provide fallback
      const baseUrl = String.fromEnvironment('BASE_URL',
          defaultValue: 'http://localhost:8000');

      // Remove protocol
      var host = baseUrl.replaceAll(RegExp(r'https?://'), '');

      // Remove port and path
      host = host.split(':').first.split('/').first;

      // If empty or looks wrong, default to localhost
      if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
        return 'localhost';
      }

      return host;
    } catch (e) {
      debugPrint('Error extracting host, defaulting to localhost: $e');
      return 'localhost';
    }
  }

  /// Dispose resources. Call when app is closing.
  void dispose() {
    _subscription?.cancel();
    _connectionController.close();
  }
}
