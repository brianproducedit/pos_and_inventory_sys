import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../data/sync/postgres_sync_service.dart';
import '../data/local/database_helper.dart';
import '../data/remote/postgres_api_service.dart';

class SyncProvider with ChangeNotifier {
  final PostgresSyncService _syncService;
  final DatabaseHelper _dbHelper;
  final Connectivity _connectivity;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isOnline = true;
  int _pendingCount = 0;
  DateTime? _lastSyncTime;
  Timer? _periodicSyncTimer;
  Timer? _pendingCountTimer;
  bool _disposed = false;

  SyncProvider({
    PostgresSyncService? syncService,
    DatabaseHelper? dbHelper,
    Connectivity? connectivity,
  })  : _dbHelper = dbHelper ?? DatabaseHelper(),
        _syncService = syncService ??
            PostgresSyncService(
              db: dbHelper ?? DatabaseHelper(),
              api: PostgresApiService(),
            ),
        _connectivity = connectivity ?? Connectivity() {
    _initConnectivity();
    _startPendingCountUpdates();
    _startPeriodicSync();
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

      // If we just came online, trigger a sync
      if (!wasOnline && _isOnline) {
        _triggerSync();
      }

      notifyListeners();
    });

    // Check initial connectivity
    _connectivity.checkConnectivity().then((result) {
      _isOnline = result != ConnectivityResult.none;
      notifyListeners();
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

  Future<void> _updatePendingCount() async {
    if (_disposed) return; // Don't run if disposed

    try {
      final db = await _dbHelper.database;

      // Check if database is still open - must be inside try-catch
      // to handle race conditions where DB closes between check and query
      if (!db.isOpen) {
        return;
      }

      final result = await db.rawQuery(
        "SELECT COUNT(*) as count FROM sync_queue WHERE status = 'pending'",
      );
      final count = result.first['count'] as int? ?? 0;
      if (_pendingCount != count && !_disposed) {
        _pendingCount = count;
        notifyListeners();
      }
    } on PlatformException catch (e) {
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
    if (_disposed) return; // Don't run if disposed

    if (!_isOnline) {
      _errorMessage = 'No internet connection';
      notifyListeners();
      return;
    }

    if (_isLoading) return; // Prevent concurrent syncs

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

    try {
      // Check if database is accessible before syncing
      final db = await _dbHelper.database;
      if (!db.isOpen) {
        debugPrint('Sync cancelled: database is closed');
        return;
      }

      // Push local changes first
      final pushSuccess = await _syncService.syncPendingChangesBatch();

      // Then pull remote changes
      await _syncService.pullChangesSinceSeq();

      _lastSyncTime = DateTime.now();

      // Reset failure tracking on success
      _consecutiveFailures = 0;
      _lastFailureTime = null;

      if (!pushSuccess) {
        _errorMessage = 'Some changes failed to sync';
      }

      // Update pending count after sync
      await _updatePendingCount();
    } on PlatformException catch (e) {
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
      if (e is PlatformException &&
          (e.message?.contains('database_closed') ?? false)) {
        debugPrint('Background sync skipped: database closed');
      } else {
        debugPrint('Background sync failed: $e');
      }
    });
  }

  /// Trigger an immediate sync attempt (useful after making changes)
  Future<void> syncNow() async {
    // Reset backoff when user manually requests sync
    resetFailureTracking();
    await sync();
    await _updatePendingCount();
  }

  /// Force refresh pending count (called after local changes)
  Future<void> refreshPendingCount() => _updatePendingCount();

  @override
  void dispose() {
    _disposed = true;
    _periodicSyncTimer?.cancel();
    _pendingCountTimer?.cancel();
    _periodicSyncTimer = null;
    _pendingCountTimer = null;
    super.dispose();
  }
}
