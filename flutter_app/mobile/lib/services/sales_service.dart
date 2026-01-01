import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../config/env.dart';

/// Exception for network-related errors that can be handled gracefully
class SalesNetworkException implements Exception {
  final String message;
  final bool isOffline;
  final bool isTimeout;

  SalesNetworkException(this.message,
      {this.isOffline = false, this.isTimeout = false});

  @override
  String toString() => message;
}

class SalesService {
  static const String baseUrl = Env.baseUrl;
  static const Duration _defaultTimeout = Duration(seconds: 15);
  static const int _maxRetries = 3;

  final http.Client client;

  SalesService({http.Client? client}) : client = client ?? http.Client();

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  int? _normalizeStoreId(int? id) => (id != null && id == 0) ? null : id;

  /// Perform HTTP request with retry logic for transient failures
  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() request, {
    int maxRetries = _maxRetries,
    Duration timeout = _defaultTimeout,
  }) async {
    int attempt = 0;
    Exception? lastException;

    while (attempt < maxRetries) {
      attempt++;
      try {
        final response = await request().timeout(timeout);

        // Retry on server errors (5xx)
        if (response.statusCode >= 500 && attempt < maxRetries) {
          debugPrint(
              'SalesService: Server error ${response.statusCode}, retry $attempt/$maxRetries');
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }

        return response;
      } on TimeoutException catch (e) {
        debugPrint('SalesService: Timeout on attempt $attempt: $e');
        lastException = SalesNetworkException(
          'Request timed out. Please check your connection.',
          isTimeout: true,
        );
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
      } on SocketException catch (e) {
        debugPrint('SalesService: Socket error on attempt $attempt: $e');
        lastException = SalesNetworkException(
          'Unable to connect to server. Please check your network.',
          isOffline: true,
        );
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
      } on HttpException catch (e) {
        debugPrint('SalesService: HTTP error on attempt $attempt: $e');
        // Handle "Connection closed before full header was received"
        final isConnectionClosed = e.message.contains('Connection closed') ||
            e.message.contains('closed before');
        lastException = SalesNetworkException(
          isConnectionClosed
              ? 'Connection lost. Retrying...'
              : 'Network error: ${e.message}',
          isOffline: isConnectionClosed,
        );
        if (isConnectionClosed && attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
      } on http.ClientException catch (e) {
        debugPrint('SalesService: Client error on attempt $attempt: $e');
        lastException = SalesNetworkException(
          'Connection error. Please try again.',
          isOffline: true,
        );
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
      } catch (e) {
        debugPrint('SalesService: Unexpected error on attempt $attempt: $e');
        // Only retry on likely connection issues
        if (e.toString().contains('Connection') && attempt < maxRetries) {
          lastException = SalesNetworkException('Connection error: $e');
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
        rethrow;
      }
    }

    throw lastException ??
        SalesNetworkException('Request failed after $maxRetries attempts');
  }

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

    final response = await _requestWithRetry(
      () => client.post(
        Uri.parse('$baseUrl/api/sales'),
        headers: headers,
        body: jsonEncode(saleData),
      ),
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

    final response = await _requestWithRetry(
      () => client.get(uri, headers: headers),
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

    final response = await _requestWithRetry(
      () => client.get(Uri.parse('$baseUrl/api/receipts/$saleId'),
          headers: headers),
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

    final response = await _requestWithRetry(
      () => client.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }),
      timeout: const Duration(seconds: 10),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load sales analytics: ${response.statusCode}');
    }
  }
}
