import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' as services;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../data/sync/postgres_sync_service.dart';
import '../data/sync/sync_database_helper.dart';
import '../data/remote/postgres_api_service.dart';
import '../data/repositories/sync_repository.dart';
import '../db/app_database.dart';

class SyncProvider with ChangeNotifier {
  final PostgresSyncService _syncService;
  final SyncDatabaseHelper _syncDbHelper;
  final Connectivity _connectivity;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isOnline = true;
  int _pendingCount = 0;
  DateTime? _lastSyncTime;
  Timer? _periodicSyncTimer;
  Timer? _pendingCountTimer;
  Timer? _fullSyncTimer; // New timer for full data synchronization
  bool _disposed = false;

  SyncProvider({
    PostgresSyncService? syncService,
    SyncDatabaseHelper? syncDbHelper,
    AppDatabase? database,
    Connectivity? connectivity,
  })  : _syncDbHelper =
            syncDbHelper ?? SyncDatabaseHelper(database ?? AppDatabase()),
        _syncService = syncService ??
            PostgresSyncService(
              db: syncDbHelper ?? SyncDatabaseHelper(database ?? AppDatabase()),
              api: PostgresApiService(),
              syncRepo: SyncRepository(
                dbHelper: syncDbHelper ??
                    SyncDatabaseHelper(database ?? AppDatabase()),
              ),
            ),
        _connectivity = connectivity ?? Connectivity() {
    _initConnectivity();
    _startPendingCountUpdates();
    _startPeriodicSync();
    _startFullSyncTimer(); // Start full sync timer for data consistency
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isOnline => _isOnline;
  int get pendingCount => _pendingCount;
  DateTime? get lastSyncTime => _lastSyncTime;

  void _initConnectivity() {
    _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = result != ConnectivityResult.none;
      debugPrint('📡 Connectivity changed: $result (online: $_isOnline)');

      // If we just came online, trigger a sync
      if (!wasOnline && _isOnline) {
        debugPrint('✅ Just came online, triggering sync');
        _triggerSync();
      }

      notifyListeners();
    });

    // Check initial connectivity
    _connectivity.checkConnectivity().then((result) {
      _isOnline = result != ConnectivityResult.none;
      debugPrint('📡 Initial connectivity: $result (online: $_isOnline)');
      notifyListeners();

      // NOTE: We no longer trigger automatic sync on app start.
      // Login flow will trigger forceInitialSync() after authentication.
      // This prevents database locks from concurrent sync operations.
      if (_isOnline) {
        debugPrint('📡 App started online, waiting for login to trigger sync');
      }
    });
  }

  /// Start periodic updates of pending sync count
  void _startPendingCountUpdates() {
    _updatePendingCount();
    _pendingCountTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _updatePendingCount();
    });
  }

  /// Start periodic sync when online (every 5 minutes)
  void _startPeriodicSync() {
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_isOnline && !_isLoading) {
        _triggerSync();
      }
    });
  }

  /// Start full data synchronization timer (every hour) to ensure consistency across devices
  void _startFullSyncTimer() {
    _fullSyncTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (_isOnline && !_isLoading) {
        _triggerFullSync();
      }
    });
  }

  Future<void> _updatePendingCount() async {
    if (_disposed) return; // Don't run if disposed

    try {
      final items = await _syncDbHelper.getPendingSyncItems();
      final count = items.length;
      if (_pendingCount != count && !_disposed) {
        _pendingCount = count;
        notifyListeners();
      }
    } on services.PlatformException catch (e) {
      // Silently handle database_closed PlatformException - expected during app shutdown
      if (!e.message.toString().contains('database_closed') && !_disposed) {
        debugPrint('Error updating pending count: $e');
      }
    } catch (e) {
      // Handle any other exceptions
      if (!_disposed) {
        debugPrint('Error updating pending count: $e');
      }
    }
  }

  /// Track consecutive sync failures for exponential backoff
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 5;
  DateTime? _lastFailureTime;

  Future<void> sync() async {
    debugPrint('🔄 SyncProvider: sync() called');
    if (_disposed) {
      debugPrint('⚠️ SyncProvider disposed, aborting');
      return;
    }

    if (!_isOnline) {
      debugPrint('❌ Not online, aborting sync');
      _errorMessage = 'No internet connection';
      notifyListeners();
      return;
    }

    if (_isLoading) {
      debugPrint('⚠️ Sync already in progress');
      return;
    }

    // Exponential backoff after consecutive failures
    if (_consecutiveFailures > 0 && _lastFailureTime != null) {
      final backoffSeconds = _calculateBackoff(_consecutiveFailures);
      final timeSinceFailure = DateTime.now().difference(_lastFailureTime!);
      if (timeSinceFailure.inSeconds < backoffSeconds) {
        debugPrint(
            'Sync: backing off for ${backoffSeconds - timeSinceFailure.inSeconds}s after $_consecutiveFailures failures');
        return;
      }
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    debugPrint('🚀 Starting sync operation...');
    try {
      // NOTE: Database accessibility is checked inside the sync service methods.
      // We don't check here to avoid opening unnecessary raw sqflite connections
      // that could conflict with ongoing sync operations.

      // Push local changes first
      debugPrint('⬆️ Pushing local changes...');
      final pushSuccess = await _syncService.syncPendingChangesBatch();
      debugPrint('⬆️ Push result: $pushSuccess');

      // Then pull remote changes
      debugPrint('⬇️ Pulling remote changes...');
      await _syncService.pullChangesSinceSeq();
      debugPrint('⬇️ Pull complete');

      _lastSyncTime = DateTime.now();
      debugPrint('✅ Sync completed successfully at $_lastSyncTime');

      // Reset failure tracking on success
      _consecutiveFailures = 0;
      _lastFailureTime = null;

      if (!pushSuccess) {
        _errorMessage = 'Some changes failed to sync';
      }

      // Update pending count after sync
      await _updatePendingCount();

      // Notify listeners that sync is complete
      await onSyncComplete?.call();
    } on services.PlatformException catch (e) {
      // Silently handle database_closed - expected during app shutdown
      if (e.message?.contains('database_closed') ?? false) {
        debugPrint('Sync cancelled: database closed during operation');
      } else {
        _handleSyncFailure('Platform error: ${e.message}');
      }
    } catch (e) {
      _handleSyncFailure(_getReadableErrorMessage(e));
    } finally {
      if (!_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Calculate exponential backoff delay in seconds
  int _calculateBackoff(int failures) {
    // Base: 5s, doubles each failure up to max 5 minutes
    return (5 * (1 << (failures - 1).clamp(0, 6))).clamp(5, 300);
  }

  /// Handle sync failure with tracking
  void _handleSyncFailure(String message) {
    _consecutiveFailures =
        (_consecutiveFailures + 1).clamp(0, _maxConsecutiveFailures);
    _lastFailureTime = DateTime.now();
    _errorMessage = message;
    debugPrint('Sync error (failure $_consecutiveFailures): $message');
  }

  /// Convert technical errors to user-friendly messages
  String _getReadableErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('connection closed') ||
        errorStr.contains('closed before') ||
        errorStr.contains('connection reset')) {
      return 'Connection lost. Will retry automatically.';
    }
    if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
      return 'Server is slow to respond. Will retry.';
    }
    if (errorStr.contains('socket') || errorStr.contains('network')) {
      return 'Network error. Check your connection.';
    }
    if (errorStr.contains('offline')) {
      return 'You are offline. Changes saved locally.';
    }
    if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
      return 'Session expired. Please log in again.';
    }
    if (errorStr.contains('500') ||
        errorStr.contains('502') ||
        errorStr.contains('503') ||
        errorStr.contains('504')) {
      return 'Server error. Will retry automatically.';
    }

    // For other errors, show a generic message
    return 'Sync failed. Will retry automatically.';
  }

  /// Force reset failure tracking (e.g., after user manually triggers sync)
  void resetFailureTracking() {
    _consecutiveFailures = 0;
    _lastFailureTime = null;
  }

  void _triggerSync() {
    // Trigger sync in background without blocking UI
    sync().catchError((e) {
      // Silently ignore database_closed errors in background sync
      if (e is services.PlatformException &&
          (e.message?.contains('database_closed') ?? false)) {
        debugPrint('Background sync skipped: database closed');
      } else {
        debugPrint('Background sync failed: $e');
      }
    });
  }

  /// Trigger full data synchronization to ensure consistency across all devices
  void _triggerFullSync() {
    debugPrint('🔄 Triggering full data synchronization for consistency');
    forceInitialSync().catchError((e) {
      // Silently ignore database_closed errors in background sync
      if (e is services.PlatformException &&
          (e.message?.contains('database_closed') ?? false)) {
        debugPrint('Background full sync skipped: database closed');
      } else {
        debugPrint('Background full sync failed: $e');
      }
      return false;
    });
  }

  /// Trigger an immediate sync attempt (useful after making changes)
  Future<void> syncNow() async {
    // Reset backoff when user manually requests sync
    resetFailureTracking();
    await sync();
    await _updatePendingCount();
  }

  /// Trigger a full data synchronization to ensure complete consistency across devices
  /// This fetches ALL data from the server and updates the local database
  Future<void> syncFullData() async {
    debugPrint(
        '🔄 SyncProvider: syncFullData() called - full data synchronization');
    // Reset backoff when user manually requests full sync
    resetFailureTracking();
    await forceInitialSync();
    await _updatePendingCount();
  }

  /// Force refresh pending count (called after local changes)
  Future<void> refreshPendingCount() => _updatePendingCount();

  /// Callback to notify when sync completes (useful for reloading data)
  Future<void> Function()? onSyncComplete;

  /// Force initial sync - fetches all data from server regardless of local state.
  /// This should be called after login to ensure all data is fetched.
  /// Returns true if sync was successful.
  Future<bool> forceInitialSync() async {
    debugPrint(
        '🔄 SyncProvider: forceInitialSync() called - FULL DATA SYNCHRONIZATION');
    if (_disposed) {
      debugPrint('⚠️ SyncProvider disposed, aborting');
      return false;
    }

    if (!_isOnline) {
      debugPrint('❌ Not online, cannot perform initial sync');
      _errorMessage = 'No internet connection';
      notifyListeners();
      return false;
    }

    if (_isLoading) {
      debugPrint('⚠️ Sync already in progress');
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('🚀 Starting forced initial sync...');

      // Push any local changes first
      debugPrint('⬆️ Pushing local changes...');
      await _syncService.syncPendingChangesBatch();

      // Force full data fetch from server
      debugPrint('📥 Forcing full data sync from server...');
      await _syncService.performInitialSync();

      _lastSyncTime = DateTime.now();
      debugPrint('✅ Initial sync completed successfully at $_lastSyncTime');

      // Reset failure tracking
      _consecutiveFailures = 0;
      _lastFailureTime = null;

      // Notify listeners that sync is complete
      await onSyncComplete?.call();

      return true;
    } catch (e) {
      debugPrint('❌ Initial sync failed: $e');
      _handleSyncFailure(_getReadableErrorMessage(e));
      return false;
    } finally {
      if (!_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _periodicSyncTimer?.cancel();
    _pendingCountTimer?.cancel();
    _fullSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _pendingCountTimer = null;
    _fullSyncTimer = null;
    super.dispose();
  }
}
