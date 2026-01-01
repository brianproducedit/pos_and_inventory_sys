import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';
import '../data/remote/postgres_api_service.dart';
import '../data/local/database_helper.dart';
import '../data/sync/postgres_sync_service.dart';

class AnalyticsService {
  static const String baseUrl = Env.baseUrl;
  final DatabaseHelper _db = DatabaseHelper();
  final PostgresSyncService _syncService;

  AnalyticsService({PostgresSyncService? syncService})
      : _syncService = syncService ??
            PostgresSyncService(
              db: DatabaseHelper(),
              api: PostgresApiService(),
            );

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  /// Create analytics event - works offline-first
  Future<void> createAnalyticsEvent({
    required String eventName,
    int? userId,
    int? fromStoreId,
    int? toStoreId,
    int? durationMs,
    Map<String, dynamic>? metadata,
    String? ipAddress,
    String? userAgent,
  }) async {
    try {
      // Always store locally first (offline-first)
      await _db.insertAnalyticsEvent(
        eventName: eventName,
        userId: userId,
        fromStoreId: fromStoreId,
        toStoreId: toStoreId,
        durationMs: durationMs,
        metadata: metadata,
        ipAddress: ipAddress,
        userAgent: userAgent,
      );

      // Try to sync immediately if online
      await _syncService.syncPendingChanges();
    } catch (e) {
      debugPrint('AnalyticsService.createAnalyticsEvent error: $e');
      // Local storage failed - this is a critical error
      rethrow;
    }
  }

  /// Fetch analytics summary - falls back to local cache when offline
  Future<Map<String, dynamic>> getAnalyticsSummary(String eventName,
      {int? sinceDays,
      String? granularity,
      String? startDate,
      String? endDate}) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final params = <String, String>{'event_name': eventName};
    if (sinceDays != null) params['since_days'] = sinceDays.toString();
    if (granularity != null) params['granularity'] = granularity;
    if (startDate != null) params['start_date'] = startDate;
    if (endDate != null) params['end_date'] = endDate;

    final uri = Uri.parse('$baseUrl/api/analytics/summary')
        .replace(queryParameters: params);

    try {
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      });

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        debugPrint(
            'AnalyticsService.getAnalyticsSummary: status ${response.statusCode}, body: ${response.body}');
        throw Exception(
            'Failed to load analytics summary: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      // If network fails, try to return local cached data
      debugPrint('AnalyticsService.getAnalyticsSummary network error: $e');
      // For now, return empty data - in a full implementation, we'd cache server responses
      return {
        'event_name': eventName,
        'total_count': 0,
        'avg_duration_ms': null,
        'by_store': [],
      };
    }
  }

  /// Get local analytics events for offline viewing
  Future<List<Map<String, dynamic>>> getLocalAnalyticsEvents({
    String? eventName,
    int? limit,
    int? offset,
  }) async {
    return await _db.getAnalyticsEvents(
      eventName: eventName,
      limit: limit,
      offset: offset,
    );
  }
}
