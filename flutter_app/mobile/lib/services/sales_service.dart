import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../config/env.dart';

class SalesService {
  static const String baseUrl = Env.baseUrl;

  final http.Client client;

  SalesService({http.Client? client}) : client = client ?? http.Client();

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  int? _normalizeStoreId(int? id) => (id != null && id == 0) ? null : id;

  Future<Map<String, dynamic>> createSale(Map<String, dynamic> saleData,
      {int? storeId}) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    // Prefer explicit storeId param; otherwise use persisted current_store_id
    int? sid = storeId;
    if (sid == null) {
      final prefs = await SharedPreferences.getInstance();
      sid = prefs.getInt('current_store_id');
    }
    sid = _normalizeStoreId(sid);
    if (sid != null) headers['X-Store-ID'] = sid.toString();

    // Debug: log outgoing X-Store-ID header for this request (non-sensitive)
    debugPrint('SalesService.createSale: X-Store-ID=${headers['X-Store-ID']}');

    final response = await client.post(
      Uri.parse('$baseUrl/api/sales'),
      headers: headers,
      body: jsonEncode(saleData),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create sale: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> getSales({int? storeId}) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    storeId = _normalizeStoreId(storeId);
    if (storeId != null) {
      headers['X-Store-ID'] = storeId.toString();
    }

    // Debug: log outgoing X-Store-ID for this request
    debugPrint(
        'SalesService.getSales: X-Store-ID=${headers['X-Store-ID']} uri=$storeId');

    final uri = storeId != null
        ? Uri.parse('$baseUrl/api/sales?store_id=$storeId')
        : Uri.parse('$baseUrl/api/sales');

    final response = await client.get(
      uri,
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => item as Map<String, dynamic>).toList();
    } else {
      throw Exception('Failed to load sales');
    }
  }

  Future<Map<String, dynamic>> getReceipt(int saleId, {int? storeId}) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    // Prefer explicit storeId param; otherwise use persisted current_store_id
    int? sid = storeId;
    if (sid == null) {
      final prefs = await SharedPreferences.getInstance();
      sid = prefs.getInt('current_store_id');
    }
    sid = _normalizeStoreId(sid);
    if (sid != null) headers['X-Store-ID'] = sid.toString();

    // Debug: log outgoing X-Store-ID for receipt request
    debugPrint('SalesService.getReceipt: X-Store-ID=${headers['X-Store-ID']}');

    final response = await client.get(
      Uri.parse('$baseUrl/api/receipts/$saleId'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load receipt');
    }
  }

  Future<Map<String, dynamic>> getSalesAnalytics({int? storeId}) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    storeId = _normalizeStoreId(storeId);

    final uri = storeId != null
        ? Uri.parse('$baseUrl/api/analytics/sales?store_id=$storeId')
        : Uri.parse('$baseUrl/api/analytics/sales');

    // Robustness: retry a couple of times for transient network/server issues
    const maxAttempts = 3;
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final response = await client.get(uri, headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else {
          throw Exception(
              'Failed to load sales analytics: ${response.statusCode}');
        }
      } catch (e) {
        // Catch common transient network errors and retry with small backoff
        if (attempt >= maxAttempts) {
          debugPrint('getSalesAnalytics: failed after $attempt attempts: $e');
          rethrow;
        }
        debugPrint('getSalesAnalytics: attempt $attempt failed: $e — retrying');
        await Future.delayed(Duration(milliseconds: 200 * attempt));
        continue;
      }
    }
  }
}
