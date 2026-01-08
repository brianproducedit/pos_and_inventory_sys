import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobile/services/time_service.dart';
import '../services/analytics_service.dart';
import '../data/repositories/analytics_repository_v2.dart' as v2;
import '../db/app_database.dart';
import 'store_provider.dart';
import 'auth_provider.dart';

class AnalyticsProvider with ChangeNotifier {
  final v2.AnalyticsRepository _analyticsRepo;
  final AnalyticsService _analyticsService;

  AnalyticsProvider({
    required v2.AnalyticsRepository analyticsRepository,
    AnalyticsService? analyticsService,
  })  : _analyticsRepo = analyticsRepository,
        _analyticsService = analyticsService ?? AnalyticsService();

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
    if (_authProvider?.role != UserRole.superadmin) {
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
    if (_authProvider?.role != UserRole.superadmin) {
      _errorMessage =
          'Access denied: Store comparison requires superadmin privileges';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Calculate date range (last 30 days)
      final endDate = TimeService.instance.now();
      final startDate = endDate.subtract(const Duration(days: 30));

      // Get store comparison data from V2 repository
      final storePerformance = await _analyticsRepo.getStoreComparison(
        startDate: startDate,
        endDate: endDate,
      );

      // Store in a special field for store comparison view
      _salesData = {
        'store_comparison': storePerformance
            .map((s) => {
                  'store_id': s.storeId,
                  'store_name': s.storeName,
                  'total_sales': s.totalSales,
                  'total_revenue': s.totalRevenue,
                  'average_order_value': s.averageOrderValue,
                })
            .toList(),
      };

      debugPrint(
          'AnalyticsProvider: loaded comparison for ${storePerformance.length} stores');
    } catch (e) {
      _errorMessage = _getReadableErrorMessage(e);
      debugPrint('Error loading store comparison: $e');
      _salesData = {'store_comparison': []};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAnalytics({int? storeId}) async {
    // Prevent concurrent calls
    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Calculate date range for analytics (last 30 days by default)
      final endDate = TimeService.instance.now();
      final startDate = endDate.subtract(const Duration(days: 30));

      // Fetch summary from local repository (fully offline)
      final summary = await _analyticsRepo.getSalesSummary(
        storeId: storeId,
        startDate: startDate,
        endDate: endDate,
      );

      // Fetch top products
      final topProducts = await _analyticsRepo.getTopProducts(
        storeId: storeId,
        startDate: startDate,
        endDate: endDate,
        limit: 10,
      );

      // Fetch recent sales
      final recentSales = await _analyticsRepo.getRecentSales(
        storeId: storeId,
        limit: 10,
      );

      // Fetch low stock alerts
      final lowStock = await _analyticsRepo.getLowStockProducts(
        storeId: storeId,
        threshold: 10,
      );

      // Fetch sales by period for daily sales chart
      final salesByPeriod = await _analyticsRepo.getSalesByPeriod(
        storeId: storeId,
        startDate: startDate,
        endDate: endDate,
        granularity: 'day',
      );

      // Build response data structure
      _salesData = {
        'total_sales': summary.totalSales,
        'total_revenue': summary.totalRevenue,
        'average_sale': summary.averageOrderValue,
        'daily_sales': salesByPeriod
            .map((p) => {
                  'date': p.period,
                  'count': p.count,
                  'revenue': p.revenue,
                })
            .toList(),
        'cash_sales': summary.cashSales,
        'card_sales': summary.cardSales,
        'mobile_sales': summary.mobileSales,
        'is_offline': false,
      };

      _recentSales = recentSales
          .map((sale) => {
                'id': sale.id,
                'transaction_number': sale.transactionNumber,
                'total_amount': sale.totalAmount,
                'payment_method': sale.paymentMethod,
                'created_at': sale.createdAt.toIso8601String(),
                'store_id': sale.storeId,
              })
          .toList();

      _topProducts = topProducts
          .map((p) => {
                'product_id': p.productId,
                'product_name': p.productName,
                'quantity_sold': p.quantitySold,
                'revenue': p.revenue,
              })
          .toList();

      _inventoryAlerts = lowStock
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'stock_quantity': p.stockQuantity,
                'price': p.price,
              })
          .toList();

      debugPrint(
          'AnalyticsProvider.loadAnalytics: loaded ${summary.totalSales} sales, ${topProducts.length} top products, ${lowStock.length} alerts');
    } catch (e) {
      final userFriendlyMessage = _getReadableErrorMessage(e);
      debugPrint('Error loading analytics: $e');
      _errorMessage = userFriendlyMessage;

      // Set default values on error
      _salesData = {
        'total_sales': 0,
        'total_revenue': 0.0,
        'average_sale': 0.0,
        'daily_sales': [],
      };
      _recentSales = [];
      _topProducts = [];
      _inventoryAlerts = [];
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
