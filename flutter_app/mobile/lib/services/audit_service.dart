import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';

/// AuditService handles audit log operations via API.
///
/// This service is now simplified to work directly with the backend API.
/// Audit logs are not stored locally since they're server-side records.
class AuditService {
  static const String baseUrl = Env.baseUrl;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  /// Log an audit event to the backend
  ///
  /// This sends the audit event directly to the server. If offline,
  /// audit events are not stored locally (they're server-side records).
  Future<void> logAuditEvent({
    required int userId,
    required String action,
    required String resourceType,
    int? resourceId,
    Map<String, dynamic>? details,
    String? ipAddress,
    String? userAgent,
    int? storeId,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        debugPrint(
            '📝 Audit event skipped (offline): $action on $resourceType');
        return;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/audit-logs'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user_id': userId,
          'action': action,
          'resource_type': resourceType,
          'resource_id': resourceId,
          'details': details,
          'ip_address': ipAddress,
          'user_agent': userAgent,
          'store_id': storeId,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint('📝 Audit event failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('📝 Audit event error: $e');
      // Non-critical - fail silently
    }
  }

  Future<Map<String, dynamic>> getAuditLogs({
    int? userId,
    String? action,
    String? resourceType,
    DateTime? startDate,
    DateTime? endDate,
    int? storeId,
    int skip = 0,
    int limit = 50,
  }) async {
    final token = await _getToken();

    // If no token (offline mode), return empty result
    if (token == null) {
      return {
        'logs': <Map<String, dynamic>>[],
        'total_count': 0,
        'offline': true,
      };
    }

    final queryParams = <String, String>{};
    if (userId != null) queryParams['user_id'] = userId.toString();
    if (action != null) queryParams['action'] = action;
    if (resourceType != null) queryParams['resource_type'] = resourceType;
    if (storeId != null) queryParams['store_id'] = storeId.toString();
    if (startDate != null) {
      queryParams['start_date'] = startDate.toIso8601String();
    }
    if (endDate != null) queryParams['end_date'] = endDate.toIso8601String();
    queryParams['skip'] = skip.toString();
    queryParams['limit'] = limit.toString();

    final uri = Uri.parse('$baseUrl/api/audit-logs')
        .replace(queryParameters: queryParams);

    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final result = decoded is List
            ? {'logs': decoded, 'total_count': decoded.length}
            : decoded as Map<String, dynamic>;

        return result;
      } else {
        throw Exception(
            'Failed to load audit logs: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('📝 getAuditLogs error: $e');
      // Return empty result on error
      return {
        'logs': <Map<String, dynamic>>[],
        'total_count': 0,
        'error': e.toString(),
      };
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
