import 'dart:async';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'sync_service.dart';
import '../db/app_database.dart';
import '../data/local/database_helper.dart';
import '../data/remote/postgres_api_service.dart';
import '../data/sync/postgres_sync_service.dart';

const String syncTaskName = 'syncTask';

/// Entry point for WorkManager background isolate
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      return await runBackgroundTask();
    } catch (e) {
      // Swallow and return false to indicate task failed — WorkManager may retry
      return false;
    }
  });
}

/// Run the background sync task using injectable factories.
/// Provided for testing so dependencies can be mocked.
Future<bool> runBackgroundTask({
  FutureOr<dynamic> Function()? openDb,
  FutureOr<dynamic> Function(dynamic service)? syncServiceFactory,
}) async {
  // Default behavior: use DatabaseHelper and PostgresSyncService
  openDb ??= () async => DatabaseHelper();
  syncServiceFactory ??= (service) => PostgresSyncService(
      db: service as DatabaseHelper, api: PostgresApiService());

  final dbHelper = await openDb();
  try {
    final serviceOrFuture = syncServiceFactory(dbHelper);
    final dynamic service =
        serviceOrFuture is Future ? (await serviceOrFuture) : serviceOrFuture;
    final ok = await syncUsing(service);
    return ok;
  } catch (e) {
    // Log but don't crash on background sync errors
    print('Background sync task failed: $e');
    return false;
  }
  // NOTE: We intentionally do NOT close the database here.
  // The DatabaseHelper uses a singleton pattern, and closing it here would
  // cause database_closed exceptions in foreground operations.
  // The database will be properly managed by the app lifecycle.
}

/// Registers the background worker using the given Workmanager instance.
/// Separated for testability: tests can provide a fake Workmanager.
void registerBackgroundWork(Workmanager wm,
    {Duration frequency = const Duration(hours: 6),
    bool isInDebugMode = false}) {
  try {
    print(
        'Registering WorkManager sync task (frequency: $frequency, debug: $isInDebugMode)');
    wm.initialize(callbackDispatcher, isInDebugMode: isInDebugMode);
    wm.registerPeriodicTask(
      'pos_sync_periodic',
      syncTaskName,
      frequency: frequency,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  } catch (e) {
    // Don't crash the app if Workmanager isn't available in this environment
    // but surface a debug message for operators.
    // Note: we don't import flutter foundation here to avoid bringing Flutter
    // into test-only code.
    print('WorkManager initialization failed: $e');
  }
}

/// Core sync logic extracted for easier testing
Future<bool> syncUsing(dynamic service) async {
  // Support multiple test and production service shapes. Prefer calling
  // syncPendingChangesBatch() when available, otherwise fall back to syncPendingChanges().
  try {
    bool pushOk = false;

    try {
      // Try preferred API: batch sync with checkpointing
      final res = await service.syncPendingChangesBatch();
      if (res is bool) pushOk = res;
    } catch (e) {
      // Fallback to syncPendingChanges()
      try {
        final res = await service.syncPendingChanges();
        if (res is bool) pushOk = res;
      } catch (e) {
        // No suitable push method
        return false;
      }
    }

    // Attempt a simple pull if possible (non-fatal)
    try {
      // Prefer calling pullChangesSinceSeq on the provided service if available
      try {
        final maybePull = (service as dynamic).pullChangesSinceSeq;
        if (maybePull is Function) {
          await maybePull();
        } else {
          // Fallback to API fetch when a token exists
          final secure = const FlutterSecureStorage();
          final token = await secure.read(key: 'access_token');
          if (token != null) {
            final api = PostgresApiService();
            await api.fetchInitialData(token: token);
          }
        }
      } catch (_) {
        // If accessing service.pullChangesSinceSeq throws, fall back to API fetch
        final secure = const FlutterSecureStorage();
        final token = await secure.read(key: 'access_token');
        if (token != null) {
          final api = PostgresApiService();
          await api.fetchInitialData(token: token);
        }
      }
    } catch (_) {
      // Non-fatal
    }

    return pushOk;
  } catch (e) {
    return false;
  }
}

/// Registers a connectivity listener to trigger an immediate sync when the
/// device regains connectivity (non-none). Returns the [StreamSubscription]
/// so callers (including tests) can cancel the subscription.
StreamSubscription<ConnectivityResult> registerConnectivityListener(
    Connectivity connectivity,
    {FutureOr<void> Function()? onConnected}) {
  final sub = connectivity.onConnectivityChanged.listen((result) async {
    if (result != ConnectivityResult.none) {
      try {
        if (onConnected != null) {
          await onConnected();
        } else {
          // Default behavior: run the background task using default factories
          await runBackgroundTask();
        }
      } catch (e) {
        // Swallow to avoid crashing connectivity handler
        print('Connectivity handler failed: $e');
      }
    }
  });
  return sub;
}
