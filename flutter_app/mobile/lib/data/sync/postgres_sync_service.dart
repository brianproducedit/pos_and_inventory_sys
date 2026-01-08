import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sync_database_helper.dart';
import '../remote/postgres_api_service.dart';
import '../repositories/sync_repository.dart';

/// Lock status information for debugging
class SyncLockStatus {
  final bool isSyncing;
  final DateTime? lockAcquiredAt;
  final String? currentOperation;

  SyncLockStatus({
    required this.isSyncing,
    this.lockAcquiredAt,
    this.currentOperation,
  });

  @override
  String toString() =>
      'SyncLockStatus(isSyncing: $isSyncing, lockAcquiredAt: $lockAcquiredAt, currentOperation: $currentOperation)';
}

class PostgresSyncService {
  final SyncDatabaseHelper db;
  final PostgresApiService api;
  final SyncRepository syncRepo;
  final FlutterSecureStorage secureStorage;
  final http.Client httpClient;
  final Connectivity connectivity;

  /// Lock to prevent concurrent sync operations which can cause database lock issues
  static bool _isSyncing = false;

  /// Track when the lock was acquired for debugging
  static DateTime? _lockAcquiredAt;

  /// Track the current operation for debugging
  static String? _currentOperation;

  /// Tables that exist in Drift schema (app_database.dart):
  /// users, stores, products, sales, sale_items, inventory_logs,
  /// sync_queue, sync_conflicts, sync_meta
  ///
  /// Tables NOT in Drift (skip operations on these):
  /// analytics_events, settings, sync_errors, transactions, transaction_items

  PostgresSyncService({
    required this.db,
    required this.api,
    required this.syncRepo,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
    Connectivity? connectivity,
  })  : secureStorage = secureStorage ?? const FlutterSecureStorage(),
        httpClient = httpClient ?? http.Client(),
        connectivity = connectivity ?? Connectivity();

  /// Maximum time a sync operation should hold the lock before being considered stale
  static const Duration _maxLockDuration = Duration(minutes: 5);

  /// Get the current sync lock status for debugging
  static SyncLockStatus getLockStatus() {
    return SyncLockStatus(
      isSyncing: _isSyncing,
      lockAcquiredAt: _lockAcquiredAt,
      currentOperation: _currentOperation,
    );
  }

  /// Check if the lock appears to be stale (held for too long)
  static bool _isLockStale() {
    if (!_isSyncing || _lockAcquiredAt == null) return false;
    final elapsed = DateTime.now().difference(_lockAcquiredAt!);
    return elapsed > _maxLockDuration;
  }

  /// Force release a stale lock (use with caution - only for recovery scenarios)
  static void forceReleaseStaleLock() {
    if (_isLockStale()) {
      debugPrint(
          '⚠️ Force releasing stale sync lock (held since $_lockAcquiredAt for $_currentOperation)');
      _isSyncing = false;
      _lockAcquiredAt = null;
      _currentOperation = null;
    }
  }

  /// Acquire the sync lock, returns true if lock acquired, false if already syncing
  static Future<bool> _acquireSyncLock({String? operation}) async {
    // Check for stale lock and release if necessary
    if (_isLockStale()) {
      debugPrint(
          '⚠️ Detected stale sync lock (held since $_lockAcquiredAt), releasing');
      forceReleaseStaleLock();
    }

    if (_isSyncing) {
      final lockInfo =
          _lockAcquiredAt != null ? ' (locked since $_lockAcquiredAt)' : '';
      final opInfo = _currentOperation != null ? ' for $_currentOperation' : '';
      debugPrint(
          'PostgresSyncService: Sync already in progress$opInfo$lockInfo, skipping');
      return false;
    }
    _isSyncing = true;
    _lockAcquiredAt = DateTime.now();
    _currentOperation = operation;
    debugPrint(
        '🔒 Sync lock acquired for: ${operation ?? "unknown operation"}');
    return true;
  }

  /// Release the sync lock
  static void _releaseSyncLock() {
    final duration = _lockAcquiredAt != null
        ? DateTime.now().difference(_lockAcquiredAt!).inMilliseconds
        : 0;
    debugPrint(
        '🔓 Sync lock released (held for ${duration}ms by $_currentOperation)');
    _isSyncing = false;
    _lockAcquiredAt = null;
    _currentOperation = null;
  }

  /// Batch variant that aggregates pending queue items into a single /api/sync/push
  /// request and applies server responses (id_map, conflicts, applied) atomically.
  /// Uses client_seq for checkpointing to ensure no missed changes on retry.
  Future<bool> syncPendingChangesBatch({int limit = 100}) async {
    // Prevent concurrent sync operations - this is the primary cause of database lock warnings
    if (!await _acquireSyncLock(operation: 'syncPendingChangesBatch')) {
      return false;
    }

    try {
      // Check connectivity
      final conn = await connectivity.checkConnectivity();
      if (conn == ConnectivityResult.none) {
        debugPrint('syncPendingChangesBatch: No connectivity, skipping push');
        return false;
      }

      // Check token
      final token = await secureStorage.read(key: 'access_token');
      if (token == null) {
        debugPrint('syncPendingChangesBatch: No auth token, skipping push');
        return false;
      }

      // Use the new SyncRepository method for batch sync operations
      debugPrint(
          'syncPendingChangesBatch: Starting push with token and limit=$limit');
      final result = await syncRepo.processBatchSyncData(
          token: token, api: api, limit: limit);
      debugPrint('syncPendingChangesBatch: Push result: $result');
      return result;
    } finally {
      _releaseSyncLock();
    }
  }

  Future<void> performInitialSync() async {
    // Prevent concurrent sync operations which cause database locks
    if (!await _acquireSyncLock(operation: 'performInitialSync')) {
      debugPrint('performInitialSync: Sync already in progress, skipping');
      return;
    }

    try {
      final token = await secureStorage.read(key: 'access_token');
      if (token == null) {
        debugPrint('performInitialSync: No token, skipping');
        return;
      }

      // Use the new SyncRepository method for initial sync operations
      final initialData = await api.fetchInitialData(token: token);
      await syncRepo.applyInitialSyncData(
        stores:
            (initialData['stores'] as List?)?.cast<Map<String, dynamic>>() ??
                [],
        users:
            (initialData['users'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        products:
            (initialData['products'] as List?)?.cast<Map<String, dynamic>>() ??
                [],
        transactions: (initialData['transactions'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [],
      );
    } catch (e, stackTrace) {
      debugPrint('❌ performInitialSync: Error: $e');
      debugPrint('Stack trace: $stackTrace');
    } finally {
      _releaseSyncLock();
    }
  }

  Future<void> pullChangesSinceSeq() async {
    // Prevent concurrent sync operations which cause database locks
    if (!await _acquireSyncLock(operation: 'pullChangesSinceSeq')) {
      debugPrint('pullChangesSinceSeq: Sync already in progress, skipping');
      return;
    }

    try {
      final token = await secureStorage.read(key: 'access_token');
      if (token == null) {
        debugPrint('pullChangesSinceSeq: No token, skipping');
        return;
      }

      // Check if this is first sync - need initial full sync
      final storeCount = await syncRepo.getStoreCount();
      final syncedStoreCount = await syncRepo.getSyncedStoreCount();

      debugPrint(
          'pullChangesSinceSeq: Store check - total=$storeCount, with_server_id=$syncedStoreCount');

      // Trigger initial sync if needed
      if (storeCount == 0 || syncedStoreCount == 0 || syncedStoreCount < 5) {
        debugPrint(
            'pullChangesSinceSeq: Initial sync needed (total_stores=$storeCount, synced_from_server=$syncedStoreCount)');

        // Fetch initial data from server
        final initialData = await api.fetchInitialData(token: token);
        final stores =
            (initialData['stores'] as List?)?.cast<Map<String, dynamic>>() ??
                [];
        final users =
            (initialData['users'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final products =
            (initialData['products'] as List?)?.cast<Map<String, dynamic>>() ??
                [];
        final transactions = (initialData['transactions'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];

        await syncRepo.applyInitialSyncData(
          stores: stores,
          users: users,
          products: products,
          transactions: transactions,
        );
        return;
      }

      // Fetch incremental changes from server
      final lastSeq = await syncRepo.getLastServerSeq();
      final res = await api.fetchChangesSinceSeq(lastSeq, token: token);
      final changes =
          (res['changes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final headSeq = res['head_seq'] as int? ?? lastSeq;

      if (changes.isEmpty) {
        await syncRepo.setLastServerSeq(headSeq);
        return;
      }

      // Apply changes using SyncRepository
      await syncRepo.applyPullChanges(changes);
      await syncRepo.setLastServerSeq(headSeq);

      // Clean up orphaned products that have never been synced
      await syncRepo.cleanupOrphanedProducts();

      // Clean up any duplicate stores
      await syncRepo.cleanupDuplicateStoresInDb();
    } on PlatformException catch (e) {
      if (e.message?.contains('database_closed') == true) {
        debugPrint(
            'pullChangesSinceSeq: Database closed during pull (expected during hot reload)');
      } else {
        debugPrint('pullChangesSinceSeq: Platform exception: ${e.message}');
      }
    } catch (e, stackTrace) {
      debugPrint('pullChangesSinceSeq: Error pulling changes: $e');
      debugPrint('Stack trace: $stackTrace');
    } finally {
      _releaseSyncLock();
    }
  }

  // REMOVED: _syncProduct() method - replaced by SyncRepository.processBatchSyncData()

  // REMOVED: _syncStore() method - replaced by SyncRepository.processBatchSyncData()

  // REMOVED: _syncTransaction() method - replaced by SyncRepository.processBatchSyncData()

  // REMOVED: _syncUser() method - replaced by SyncRepository.processBatchSyncData()

  // NOTE: _syncAnalyticsEvent and _syncSetting methods were removed because
  // analytics_events and settings tables do NOT exist in the Drift schema.
  // Analytics are handled by AnalyticsProvider (direct API calls).
  // Settings are handled by SharedPreferences.
  // Sync queue items for these tables are marked as synced in the case statements above.

  /// Clean up duplicate products using Drift-based operations
  Future<void> cleanupDuplicateProducts() async {
    await syncRepo.cleanupDuplicateProducts();
  }
}
