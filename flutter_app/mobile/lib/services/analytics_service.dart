import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';

/// Analytics service for user behavior tracking events.
/// Uses the backend API directly for event creation and fetching.
/// Note: This is separate from sales analytics (AnalyticsRepository).
class AnalyticsService {
  static const String baseUrl = Env.baseUrl;

  AnalyticsService();

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  /// Create analytics event - sends directly to backend
  /// Falls back silently on failure (non-critical feature)
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
      final token = await _getToken();
      if (token == null) {
        debugPrint('📊 Analytics: No token, skipping event: $eventName');
        return;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/analytics'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'event_name': eventName,
          'user_id': userId,
          'from_store_id': fromStoreId,
          'to_store_id': toStoreId,
          'duration_ms': durationMs,
          'metadata': metadata,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('📊 Analytics event sent: $eventName');
      } else {
        debugPrint('📊 Analytics event failed: ${response.statusCode}');
      }
    } catch (e) {
      // Analytics events are non-critical - don't propagate errors
      debugPrint('📊 Analytics event error (non-fatal): $e');
    }
  }

  /// Fetch analytics summary from backend
  Future<Map<String, dynamic>> getAnalyticsSummary(
    String eventName, {
    int? sinceDays,
    String? granularity,
    String? startDate,
    String? endDate,
  }) async {
    final token = await _getToken();
    if (token == null) {
      debugPrint(
          '📊 Analytics: No token, returning empty summary for: $eventName');
      return {
        'event_name': eventName,
        'total_count': 0,
        'avg_duration_ms': null,
        'by_store': [],
      };
    }

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
            'AnalyticsService.getAnalyticsSummary: status ${response.statusCode}');
        throw Exception(
            'Failed to load analytics summary: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('AnalyticsService.getAnalyticsSummary network error: $e');
      return {
        'event_name': eventName,
        'total_count': 0,
        'avg_duration_ms': null,
        'by_store': [],
      };
    }
  }
}
