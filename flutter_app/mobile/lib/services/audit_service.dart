import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';
import '../data/local/database_helper.dart';

class AuditService {
  static const String baseUrl = Env.baseUrl;
  final DatabaseHelper _db = DatabaseHelper();

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  /// Log an audit event locally (for offline auditing)
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
    await _db.insertAuditLog(
      userId: userId,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      details: details,
      ipAddress: ipAddress,
      userAgent: userAgent,
      storeId: storeId,
    );
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

        // Cache logs locally for offline access
        final logs = result['logs'] as List?;
        if (logs != null) {
          for (final log in logs) {
            // Skip logs without valid user_id
            if (log['user_id'] == null) continue;

            await _db.insertAuditLog(
              userId: log['user_id'] as int,
              action: log['action'] ?? 'unknown',
              resourceType: log['resource_type'] ?? 'unknown',
              resourceId: log['resource_id'],
              details: log['details'],
              ipAddress: log['ip_address'],
              userAgent: log['user_agent'],
              storeId: log['store_id'],
            );
          }
        }

        return result;
      } else {
        throw Exception(
            'Failed to load audit logs: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      // Fall back to local cached logs
      final localLogs = await _db.getAuditLogs(
        userId: userId,
        action: action,
        resourceType: resourceType,
        limit: limit,
        offset: skip,
      );

      // Convert to the expected format
      final formattedLogs = localLogs
          .map((log) => {
                'id': log['id'],
                'user_id': log['user_id'],
                'action': log['action'],
                'resource_type': log['resource_type'],
                'resource_id': log['resource_id'],
                'details': log['details'],
                'ip_address': log['ip_address'],
                'user_agent': log['user_agent'],
                'store_id': log['store_id'],
                'created_at':
                    DateTime.fromMillisecondsSinceEpoch(log['created_at']),
              })
          .toList();

      return {
        'logs': formattedLogs,
        'total_count': formattedLogs.length,
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
