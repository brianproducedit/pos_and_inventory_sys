import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobile/services/time_service.dart';
import '../services/sales_service.dart';
import '../services/analytics_service.dart';
import '../data/local/database_helper.dart';
import 'store_provider.dart';
import 'auth_provider.dart';

class AnalyticsProvider with ChangeNotifier {
  final SalesService _salesService;
  final AnalyticsService _analyticsService;
  final DatabaseHelper _db;

  AnalyticsProvider(
      {SalesService? salesService,
      AnalyticsService? analyticsService,
      DatabaseHelper? db})
      : _salesService = salesService ?? SalesService(),
        _analyticsService = analyticsService ?? AnalyticsService(),
        _db = db ?? DatabaseHelper();

  Map<String, dynamic> _salesData = {};
  List<Map<String, dynamic>> _recentSales = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _inventoryAlerts = [];
  bool _isLoading = false;
  String? _errorMessage;
  StoreProvider? _storeProvider;
  AuthProvider? _authProvider;
  // Track last seen store id to avoid redundant refreshes when provider notifies
  int? _lastStoreId;

  int? _parseStoreId(dynamic id) {
    if (id == null) return null;
    if (id is int) return id;
    return int.tryParse(id.toString());
  }

  void _onStoreChanged() {
    final newId = _parseStoreId(_storeProvider?.currentStore?['id']);
    if (newId != _lastStoreId) {
      _lastStoreId = newId;
      // Fire-and-forget refresh for new store context
      unawaited(loadAnalyticsForCurrentStore());
    }
  }

  // Simple in-memory cache for analytics summaries: key -> (data, timestamp)
  final Map<String, Map<String, dynamic>> _summaryCache = {};
  final Duration _cacheTtl = const Duration(minutes: 5);

  String _cacheKey(String eventName,
      {int? sinceDays,
      String? granularity,
      String? startDate,
      String? endDate}) {
    return '$eventName|${sinceDays ?? ''}|${granularity ?? ''}|${startDate ?? ''}|${endDate ?? ''}';
  }

  Future<Map<String, dynamic>> _getFromCache(String key) async {
    final entry = _summaryCache[key];
    if (entry == null) return {};
    final ts = entry['_cached_at'] as DateTime?;
    if (ts == null) return {};
    if (TimeService.instance.now().difference(ts) > _cacheTtl) {
      _summaryCache.remove(key);
      return {};
    }
    return entry['data'] as Map<String, dynamic>;
  }

  void _putCache(String key, Map<String, dynamic> data) {
    _summaryCache[key] = {
      'data': data,
      '_cached_at': TimeService.instance.now()
    };
  }

  Map<String, dynamic> get salesData => _salesData;
  List<Map<String, dynamic>> get recentSales => _recentSales;
  List<Map<String, dynamic>> get topProducts => _topProducts;
  List<Map<String, dynamic>> get inventoryAlerts => _inventoryAlerts;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  // Last tracked event (useful for tests)
  String? _lastEventName;
  Map<String, dynamic>? _lastEventPayload;

  String? get lastEventName => _lastEventName;
  Map<String, dynamic>? get lastEventPayload => _lastEventPayload;

  void trackEvent(String name, Map<String, dynamic> payload) {
    _lastEventName = name;
    _lastEventPayload = payload;
    debugPrint('AnalyticsProvider.trackEvent: $name, $payload');

    // Send analytics event offline-first
    unawaited(_sendAnalyticsEvent(name, payload));

    notifyListeners();
  }

  Future<void> _sendAnalyticsEvent(
      String eventName, Map<String, dynamic> payload) async {
    try {
      final userId = _authProvider?.user?.id;
      final fromStoreId = _parseStoreId(_storeProvider?.currentStore?['id']);
      final toStoreId = payload['to_store_id'] as int?;
      final durationMs = payload['duration_ms'] as int?;
      final metadata = payload['metadata'] as Map<String, dynamic>?;

      await _analyticsService.createAnalyticsEvent(
        eventName: eventName,
        userId: userId,
        fromStoreId: fromStoreId,
        toStoreId: toStoreId,
        durationMs: durationMs,
        metadata: metadata,
      );
    } catch (e) {
      debugPrint('Failed to send analytics event: $e');
      // Analytics events are not critical - don't show errors to user
    }
  }

  void setStoreProvider(StoreProvider storeProvider) {
    // Unregister previous listener if any
    if (_storeProvider != null) {
      _storeProvider!.removeListener(_onStoreChanged);
    }
    _storeProvider = storeProvider;
    // Keep local lastStoreId in sync
    _lastStoreId = _parseStoreId(_storeProvider?.currentStore?['id']);
    // Register listener to refresh analytics when store changes
    _storeProvider!.addListener(_onStoreChanged);
    // Initial load for the current store context
    unawaited(loadAnalyticsForCurrentStore());
  }

  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
  }

  Future<void> loadAnalyticsForCurrentStore() async {
    int? storeId;
    if (_storeProvider?.currentStore != null) {
      storeId = _parseStoreId(_storeProvider!.currentStore!['id']);
    }
    // Update last seen id
    _lastStoreId = storeId;
    await loadAnalytics(storeId: storeId);
  }

  Future<void> loadCrossStoreAnalytics() async {
    // Only superadmin can load cross-store analytics
    if (_authProvider?.role != 'superadmin') {
      _errorMessage =
          'Access denied: Cross-store analytics requires superadmin privileges';
      notifyListeners();
      return;
    }

    // Load analytics without store filter for superadmin global view
    await loadAnalytics(storeId: null);
  }

  Future<void> loadStoreComparisonAnalytics() async {
    // Only superadmin can compare stores
    if (_authProvider?.role != 'superadmin') {
      _errorMessage =
          'Access denied: Store comparison requires superadmin privileges';
      notifyListeners();
      return;
    }

    // This would load comparative analytics across all stores
    // For now, we'll load global analytics
    await loadAnalytics(storeId: null);
  }

  Future<void> loadAnalytics({int? storeId}) async {
    // Prevent concurrent calls
    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Fetch server analytics with proper timeout
      final data =
          await _salesService.getSalesAnalytics(storeId: storeId).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Analytics request timed out');
        },
      );

      // Fetch local offline stats to supplement server analytics
      final localStats = await _db.getLocalTransactionStats(storeId: storeId);
      final unsyncedCount = localStats['unsynced_count'] as int? ?? 0;
      final unsyncedRevenue = localStats['unsynced_revenue'] as double? ?? 0.0;

      // Combine server + unsynced local data for accurate totals
      final serverSales = data['total_sales'] as int? ?? 0;
      final serverRevenue = (data['total_revenue'] as num?)?.toDouble() ?? 0.0;

      final totalSales = serverSales + unsyncedCount;
      final totalRevenue = serverRevenue + unsyncedRevenue;

      _salesData = {
        'total_sales': totalSales,
        'total_revenue': totalRevenue,
        'average_sale': totalSales > 0 ? totalRevenue / totalSales : 0.0,
        'daily_sales': data['daily_sales'] ?? [],
        // Track unsynced for UI display (optional)
        'unsynced_sales': unsyncedCount,
        'unsynced_revenue': unsyncedRevenue,
        'is_offline': false,
      };
      _recentSales =
          List<Map<String, dynamic>>.from(data['recent_sales'] ?? []);
      _topProducts =
          List<Map<String, dynamic>>.from(data['top_products'] ?? []);
      _inventoryAlerts =
          List<Map<String, dynamic>>.from(data['inventory_alerts'] ?? []);

      debugPrint(
          'AnalyticsProvider.loadAnalytics: server=$serverSales, unsynced=$unsyncedCount, total=$totalSales');
    } catch (e) {
      final userFriendlyMessage = _getReadableErrorMessage(e);
      debugPrint('Error loading analytics: $e');

      // Fallback to local-only stats when server is unavailable
      try {
        final localStats = await _db.getLocalTransactionStats(storeId: storeId);
        _salesData = {
          'total_sales': localStats['total_transactions'] ?? 0,
          'total_revenue': localStats['total_revenue'] ?? 0.0,
          'average_sale': localStats['average_transaction'] ?? 0.0,
          'daily_sales': [],
          'unsynced_sales': localStats['unsynced_count'] ?? 0,
          'unsynced_revenue': localStats['unsynced_revenue'] ?? 0.0,
          'is_offline': true, // Mark as offline-only data
        };
        _recentSales = [];
        _topProducts = [];
        _inventoryAlerts = [];
        // Set a softer error message since we have fallback data
        _errorMessage = userFriendlyMessage;
        _errorMessage = null;
        debugPrint(
            'AnalyticsProvider.loadAnalytics: using offline fallback data');
      } catch (localError) {
        debugPrint(
            'AnalyticsProvider.loadAnalytics: local fallback also failed: $localError');
        // Set default values if both API and local fail
        _salesData = {
          'total_sales': 0,
          'total_revenue': 0.0,
          'average_sale': 0.0,
          'daily_sales': [],
        };
        _recentSales = [];
        _topProducts = [];
        _inventoryAlerts = [];
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Call server summary endpoint and return the parsed response
  Future<Map<String, dynamic>> loadAnalyticsSummary(String eventName,
      {int? sinceDays,
      String? granularity,
      String? startDate,
      String? endDate,
      bool forceRefresh = false}) async {
    // Make sure we are requesting summary consistent with current store context
    // (analytics summaries interpret null storeId as All Stores)
    // No-op here — consumers should call with the desired store filter, but
    // keeping this comment as guidance for future maintainers.
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    final key = _cacheKey(eventName,
        sinceDays: sinceDays,
        granularity: granularity,
        startDate: startDate,
        endDate: endDate);

    if (!forceRefresh) {
      final cached = await _getFromCache(key);
      if (cached.isNotEmpty) {
        _isLoading = false;
        notifyListeners();
        return cached;
      }
    }

    try {
      final data = await _analyticsService.getAnalyticsSummary(eventName,
          sinceDays: sinceDays,
          granularity: granularity,
          startDate: startDate,
          endDate: endDate);
      _putCache(key, data);
      return data;
    } catch (e) {
      _errorMessage = _getReadableErrorMessage(e);
      debugPrint('Error loading analytics summary: $e');
      return {};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Convert technical errors to user-friendly messages
  String _getReadableErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('connection closed') ||
        errorStr.contains('closed before') ||
        errorStr.contains('connection reset')) {
      return 'Connection lost. Showing cached data.';
    }
    if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
      return 'Server slow to respond. Showing cached data.';
    }
    if (errorStr.contains('socket') || errorStr.contains('network')) {
      return 'Network error. Showing cached data.';
    }
    if (errorStr.contains('offline')) {
      return 'You are offline. Showing local data.';
    }

    return 'Unable to refresh. Showing cached data.';
  }
}
