import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';

class AuditService {
  static const String baseUrl = Env.baseUrl;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<Map<String, dynamic>> getAuditLogs({
    int? userId,
    String? action,
    String? resourceType,
    DateTime? startDate,
    DateTime? endDate,
    int skip = 0,
    int limit = 50,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final queryParams = <String, String>{};
    if (userId != null) queryParams['user_id'] = userId.toString();
    if (action != null) queryParams['action'] = action;
    if (resourceType != null) queryParams['resource_type'] = resourceType;
    if (startDate != null) {
      queryParams['start_date'] = startDate.toIso8601String();
    }
    if (endDate != null) queryParams['end_date'] = endDate.toIso8601String();
    queryParams['skip'] = skip.toString();
    queryParams['limit'] = limit.toString();

    final uri = Uri.parse('$baseUrl/api/audit-logs')
        .replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      // The backend may return either a JSON array (legacy) or an object with
      // { logs: [...], total_count: n } (current). Normalize to a Map.
      if (decoded is List) {
        return {'logs': decoded, 'total_count': decoded.length};
      }
      return decoded as Map<String, dynamic>;
    } else {
      throw Exception(
          'Failed to load audit logs: ${response.statusCode} - ${response.body}');
    }
  }

  Future<List<String>> getAuditActions() async {
    // Return the list of available audit actions
    // This could be fetched from the API or hardcoded based on the backend
    return [
      'user_login',
      'user_logout',
      'user_create',
      'user_update',
      'user_deactivate',
      'user_delete',
      'user_assign_store',
      'product_create',
      'product_update',
      'product_delete',
      'product_stock_update',
      'sale_create',
      'sale_update',
      'sale_delete',
      'sale_void',
      'store_create',
      'store_update',
      'store_delete',
      'settings_update',
      'password_change',
      'failed_login'
    ];
  }

  Future<List<String>> getResourceTypes() async {
    // Return the list of available resource types
    return ['user', 'product', 'sale', 'store', 'settings', 'auth'];
  }
}
