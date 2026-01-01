import 'dart:async';
import 'package:workmanager/workmanager.dart';
import 'package:drift/drift.dart' as drift;
import '../db/app_database.dart';
import '../data/remote/api_client.dart';
import 'sync_worker.dart';

/// Service for managing background sync operations using WorkManager
class BackgroundSyncService {
  static const String syncTaskName = 'periodic_sync_task';
  static const String uniqueTaskName = 'com.pos.sync';

  /// Initialize WorkManager and register background tasks
  static Future<void> initialize() async {
    // Initialize WorkManager
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false, // Set to true for debugging
    );

    print('BackgroundSyncService: WorkManager initialized');
  }

  /// Register periodic sync task
  /// Runs every 15 minutes when online
  static Future<void> registerPeriodicSync({
    Duration frequency = const Duration(minutes: 15),
  }) async {
    await Workmanager().registerPeriodicTask(
      uniqueTaskName,
      syncTaskName,
      frequency: frequency,
      constraints: Constraints(
        networkType: NetworkType.connected, // Only run when connected
        requiresBatteryNotLow: true, // Don't drain battery
        requiresCharging: false,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
    );

    print(
        'BackgroundSyncService: Periodic sync registered (every ${frequency.inMinutes} minutes)');
  }

  /// Cancel periodic sync
  static Future<void> cancelPeriodicSync() async {
    await Workmanager().cancelByUniqueName(uniqueTaskName);
    print('BackgroundSyncService: Periodic sync cancelled');
  }

  /// Trigger immediate one-time sync
  static Future<void> triggerImmediateSync() async {
    await Workmanager().registerOneOffTask(
      '${uniqueTaskName}_immediate',
      syncTaskName,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );

    print('BackgroundSyncService: Immediate sync triggered');
  }

  /// Check if periodic sync is enabled
  static Future<bool> isPeriodicSyncEnabled() async {
    // Note: WorkManager doesn't provide a direct way to check this
    // You'd need to store this state in SharedPreferences or similar
    return true; // Placeholder
  }
}

/// Background task callback dispatcher
/// This runs in an isolate separate from the main app
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('BackgroundSync: Starting background sync task: $task');

    try {
      // Initialize database and services for background isolate
      final db = AppDatabase();
      final apiClient = ApiClient();
      final syncWorker = SyncWorker(
        db: db,
        apiClient: apiClient,
      );

      // Note: WorkManager already has network constraints
      // Connectivity is checked by WorkManager before running this task

      // Perform sync
      await syncWorker.triggerSync();

      print('BackgroundSync: Background sync completed successfully');
      return Future.value(true);
    } catch (e) {
      print('BackgroundSync: Background sync failed: $e');
      // Return false to signal failure - WorkManager will retry with backoff
      return Future.value(false);
    }
  });
}

/// Extension to manage sync settings
class SyncSettings {
  static const String _syncIntervalKey = 'sync_interval_minutes';
  static const String _syncEnabledKey = 'background_sync_enabled';
  static const String _wifiOnlyKey = 'sync_wifi_only';

  /// Get sync interval in minutes
  static Future<int> getSyncInterval(AppDatabase db) async {
    final meta = await (db.select(db.syncMeta)
          ..where((m) => m.key.equals(_syncIntervalKey)))
        .getSingleOrNull();

    return int.tryParse(meta?.value ?? '15') ?? 15;
  }

  /// Set sync interval in minutes
  static Future<void> setSyncInterval(AppDatabase db, int minutes) async {
    await db.into(db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            key: _syncIntervalKey,
            value: drift.Value(minutes.toString()),
          ),
        );

    // Re-register with new interval
    await BackgroundSyncService.registerPeriodicSync(
      frequency: Duration(minutes: minutes),
    );
  }

  /// Check if background sync is enabled
  static Future<bool> isSyncEnabled(AppDatabase db) async {
    final meta = await (db.select(db.syncMeta)
          ..where((m) => m.key.equals(_syncEnabledKey)))
        .getSingleOrNull();

    return meta?.value?.toLowerCase() == 'true';
  }

  /// Enable or disable background sync
  static Future<void> setSyncEnabled(AppDatabase db, bool enabled) async {
    await db.into(db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            key: _syncEnabledKey,
            value: drift.Value(enabled.toString()),
          ),
        );

    if (enabled) {
      final interval = await getSyncInterval(db);
      await BackgroundSyncService.registerPeriodicSync(
        frequency: Duration(minutes: interval),
      );
    } else {
      await BackgroundSyncService.cancelPeriodicSync();
    }
  }

  /// Check if sync should only occur on WiFi
  static Future<bool> isWifiOnly(AppDatabase db) async {
    final meta = await (db.select(db.syncMeta)
          ..where((m) => m.key.equals(_wifiOnlyKey)))
        .getSingleOrNull();

    return meta?.value?.toLowerCase() == 'true';
  }

  /// Set WiFi-only sync preference
  static Future<void> setWifiOnly(AppDatabase db, bool wifiOnly) async {
    await db.into(db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            key: _wifiOnlyKey,
            value: drift.Value(wifiOnly.toString()),
          ),
        );
  }
}

/// Sync statistics for monitoring
class SyncStatistics {
  final int totalSynced;
  final int pendingCount;
  final int failedCount;
  final int conflictCount;
  final DateTime? lastSuccessfulSync;
  final DateTime? lastAttemptedSync;

  SyncStatistics({
    required this.totalSynced,
    required this.pendingCount,
    required this.failedCount,
    required this.conflictCount,
    this.lastSuccessfulSync,
    this.lastAttemptedSync,
  });

  bool get hasIssues => failedCount > 0 || conflictCount > 0;
  bool get isPending => pendingCount > 0;
  bool get isHealthy => !hasIssues && pendingCount < 10;

  String getHealthStatus() {
    if (conflictCount > 0) return 'Conflicts Detected';
    if (failedCount > 0) return 'Sync Errors';
    if (pendingCount > 50) return 'Many Pending Changes';
    if (pendingCount > 0) return 'Sync Pending';
    return 'All Synced';
  }

  /// Get sync statistics from database
  static Future<SyncStatistics> fetch(AppDatabase db) async {
    final pending = await (db.select(db.syncQueue)
          ..where((q) => q.status.equals('pending')))
        .get();

    final failed = await (db.select(db.syncQueue)
          ..where((q) => q.status.equals('failed')))
        .get();

    // Count conflicts across all tables
    final conflictingUsers = await (db.select(db.users)
          ..where((u) => u.syncStatus.equals('conflict')))
        .get();
    
    final conflictingProducts = await (db.select(db.products)
          ..where((p) => p.syncStatus.equals('conflict')))
        .get();

    final conflictCount = conflictingUsers.length + conflictingProducts.length;

    // Get last sync timestamps from metadata
    final lastSuccessMeta = await (db.select(db.syncMeta)
          ..where((m) => m.key.equals('last_successful_sync')))
        .getSingleOrNull();

    final lastAttemptMeta = await (db.select(db.syncMeta)
          ..where((m) => m.key.equals('last_attempted_sync')))
        .getSingleOrNull();

    return SyncStatistics(
      totalSynced: 0, // Could track this in metadata
      pendingCount: pending.length,
      failedCount: failed.length,
      conflictCount: conflictCount,
      lastSuccessfulSync: lastSuccessMeta?.value != null 
          ? DateTime.tryParse(lastSuccessMeta!.value!)
          : null,
      lastAttemptedSync: lastAttemptMeta?.value != null
          ? DateTime.tryParse(lastAttemptMeta!.value!)
          : null,
    );
  }
}
