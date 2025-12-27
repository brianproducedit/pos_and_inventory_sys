import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';

class AnalyticsService {
  static const String baseUrl = Env.baseUrl;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  /// Fetch analytics summary for an event_name (server-side aggregate)
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
  }
}
