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
      final db = await AppDatabase.open();
      final service = SyncService(db);
      final ok = await syncUsing(service);
      await db.close();
      return ok;
    } catch (e) {
      // Swallow and return false to indicate task failed — WorkManager may retry
      return false;
    }
  });
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
