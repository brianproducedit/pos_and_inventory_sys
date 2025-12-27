import 'dart:async';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sync_service.dart';
import '../db/app_database.dart';

const String syncTaskName = 'syncTask';

/// Entry point for WorkManager background isolate
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
  FutureOr<dynamic> Function(dynamic db)? syncServiceFactory,
}) async {
  openDb ??= () => AppDatabase.open();
  syncServiceFactory ??= (db) => SyncService(db);

  final db = await openDb();
  try {
    final serviceOrFuture = syncServiceFactory(db);
    final dynamic service =
        serviceOrFuture is Future ? (await serviceOrFuture) : serviceOrFuture;
    final ok = await syncUsing(service);
    return ok;
  } finally {
    try {
      await db.close();
    } catch (_) {}
  }
}

/// Registers the background worker using the given Workmanager instance.
/// Separated for testability: tests can provide a fake Workmanager.
void registerBackgroundWork(Workmanager wm,
    {Duration frequency = const Duration(hours: 6)}) {
  try {
    wm.initialize(callbackDispatcher, isInDebugMode: false);
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
  // service is expected to have pushChanges() and pullChanges({required DateTime since})
  try {
    await service.pushChanges();

    // determine 'since' timestamp (fallback to epoch if none available)
    DateTime since;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString('last_sync_time');
      since = last != null
          ? DateTime.parse(last)
          : DateTime.fromMillisecondsSinceEpoch(0);
    } catch (_) {
      since = DateTime.fromMillisecondsSinceEpoch(0);
    }

    await service.pullChanges(since: since);
    return true;
  } catch (e) {
    return false;
  }
}
