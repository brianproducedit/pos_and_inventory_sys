import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config/env.dart';
import '../local/database_helper.dart';

/// Exception for API-related errors with connection context
class ApiConnectionException implements Exception {
  final String message;
  final bool isTimeout;
  final bool isConnectionLost;
  final int? statusCode;

  ApiConnectionException(
    this.message, {
    this.isTimeout = false,
    this.isConnectionLost = false,
    this.statusCode,
  });

  @override
  String toString() => 'ApiConnectionException: $message';

  bool get isRetryable =>
      isTimeout ||
      isConnectionLost ||
      (statusCode != null && statusCode! >= 500);
}

class PostgresApiService {
  final String baseUrl;
  final http.Client client;
  static const Duration _defaultTimeout = Duration(seconds: 15);
  static const int _maxRetries = 3;

  PostgresApiService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? Env.baseUrl,
        client = client ?? http.Client();

  /// Execute HTTP request with retry logic for transient failures
  Future<http.Response> _executeWithRetry(
    Future<http.Response> Function() request, {
    int maxRetries = _maxRetries,
    Duration timeout = _defaultTimeout,
    String? context,
  }) async {
    int attempt = 0;
    Exception? lastException;

    while (attempt < maxRetries) {
      attempt++;
      try {
        debugPrint(
            'PostgresApiService: ${context ?? 'request'} attempt $attempt/$maxRetries');
        final response = await request().timeout(timeout);

        // Retry on server errors (5xx)
        if (response.statusCode >= 500 && attempt < maxRetries) {
          debugPrint(
              'PostgresApiService: Server error ${response.statusCode}, retrying...');
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }

        return response;
      } on TimeoutException catch (e) {
        debugPrint('PostgresApiService: Timeout on attempt $attempt: $e');
        lastException = ApiConnectionException(
          'Request timed out',
          isTimeout: true,
        );
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
      } on SocketException catch (e) {
        debugPrint('PostgresApiService: Socket error on attempt $attempt: $e');
        lastException = ApiConnectionException(
          'Connection failed: ${e.message}',
          isConnectionLost: true,
        );
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
      } on HttpException catch (e) {
        debugPrint('PostgresApiService: HTTP error on attempt $attempt: $e');
        final isConnectionClosed = e.message.contains('Connection closed') ||
            e.message.contains('closed before');
        lastException = ApiConnectionException(
          e.message,
          isConnectionLost: isConnectionClosed,
        );
        if (isConnectionClosed && attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
      } on http.ClientException catch (e) {
        debugPrint('PostgresApiService: Client error on attempt $attempt: $e');
        lastException = ApiConnectionException(
          'Connection error: ${e.message}',
          isConnectionLost: true,
        );
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
      } catch (e) {
        debugPrint(
            'PostgresApiService: Unexpected error on attempt $attempt: $e');
        if (e.toString().contains('Connection') && attempt < maxRetries) {
          lastException = ApiConnectionException('Connection error: $e',
              isConnectionLost: true);
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
        rethrow;
      }
    }

    throw lastException ??
        ApiConnectionException('Request failed after $maxRetries attempts');
  }

  /// Fetch an initial snapshot of server data (products, reference data) to seed local DB.
  /// Server endpoints vary; try `/api/sync/initial` first, fallback to `/api/products`.
  Future<Map<String, dynamic>> fetchInitialData({required String token}) async {
    final headers = {'Authorization': 'Bearer $token'};
    final uri = Uri.parse('$baseUrl/api/sync/initial');

    final res = await _executeWithRetry(
      () => client.get(uri, headers: headers),
      context: 'fetchInitialData',
    );

    if (res.statusCode == 200) {
      final parsed = jsonDecode(res.body);
      if (parsed is Map<String, dynamic>) return parsed;
      if (parsed is List) return {'products': parsed};
    }

    // Fallback: fetch products list only
    final pUri = Uri.parse('$baseUrl/api/products');
    final pres = await _executeWithRetry(
      () => client.get(pUri, headers: headers),
      context: 'fetchInitialData fallback',
    );

    if (pres.statusCode == 200) {
      final parsed = jsonDecode(pres.body);
      if (parsed is List) return {'products': parsed};
      if (parsed is Map<String, dynamic> && parsed['products'] is List)
        return {'products': parsed['products']};
    }

    throw ApiConnectionException(
        'Failed to fetch initial data (${res.statusCode}, ${pres.statusCode})',
        statusCode: res.statusCode);
  }

  /// Fetch initial data and populate the provided `DatabaseHelper` in a single transaction.
  Future<void> fetchInitialDataAndSeedDB(
      {required String token, required DatabaseHelper dbHelper}) async {
    debugPrint('PostgresApiService: fetchInitialDataAndSeedDB start');
    final data = await fetchInitialData(token: token);
    debugPrint('PostgresApiService: fetched initial data keys=${data.keys}');
    final db = await dbHelper.database;

    final products =
        (data['products'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    debugPrint('PostgresApiService: seeding ${products.length} products');

    await db.transaction((txn) async {
      debugPrint('PostgresApiService: transaction started');
      final existing = await txn.query('products', limit: 1);
      if (existing.isNotEmpty) {
        // merge by server_id
        for (final p in products) {
          final serverId = p['id'] as int?;
          if (serverId == null) continue;
          final rows = await txn
              .query('products', where: 'server_id = ?', whereArgs: [serverId]);
          final now = DateTime.now().millisecondsSinceEpoch;
          final map = {
            'server_id': serverId,
            'store_id': p['store_id'],
            'name': p['name'],
            'sku': p['sku'],
            'price': p['price'],
            'stock_quantity': p['stock_quantity'],
            'is_synced': 1,
            'last_updated': now
          };
          if (rows.isEmpty) {
            await txn.insert('products', map);
          } else {
            await txn.update('products', map,
                where: 'server_id = ?', whereArgs: [serverId]);
          }
        }
      } else {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final p in products) {
          await txn.insert('products', {
            'server_id': p['id'],
            'store_id': p['store_id'],
            'name': p['name'],
            'sku': p['sku'],
            'price': p['price'],
            'stock_quantity': p['stock_quantity'],
            'is_synced': 1,
            'last_updated': now
          });
        }
      }
    });
  }

  /// Fetch the list of products (optionally since a timestamp)
  Future<List<Map<String, dynamic>>> fetchProducts(
      {DateTime? since, String? token}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final uri = since == null
        ? Uri.parse('$baseUrl/api/products')
        : Uri.parse('$baseUrl/api/products?since=${since.toIso8601String()}');

    final res = await _executeWithRetry(
      () => client.get(uri, headers: headers),
      context: 'fetchProducts',
    );

    if (res.statusCode != 200) {
      throw ApiConnectionException(
          'Failed to fetch products: ${res.statusCode}',
          statusCode: res.statusCode);
    }
    final data = jsonDecode(res.body);
    if (data is List) return data.cast<Map<String, dynamic>>();
    if (data is Map && data['products'] is List)
      return (data['products'] as List).cast<Map<String, dynamic>>();
    return [];
  }

  /// Create a product on the server and return the created object
  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> payload,
      {String? token}) async {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final uri = Uri.parse('$baseUrl/api/products');

    final res = await _executeWithRetry(
      () => client.post(uri, headers: headers, body: jsonEncode(payload)),
      context: 'createProduct',
    );

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw ApiConnectionException(
          'Failed to create product: ${res.statusCode}',
          statusCode: res.statusCode);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Update a product on the server and return the updated object
  Future<Map<String, dynamic>> updateProduct(
      int id, Map<String, dynamic> payload,
      {String? token}) async {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final uri = Uri.parse('$baseUrl/api/products/$id');

    final res = await _executeWithRetry(
      () => client.put(uri, headers: headers, body: jsonEncode(payload)),
      context: 'updateProduct',
    );

    if (res.statusCode != 200) {
      throw ApiConnectionException(
          'Failed to update product: ${res.statusCode}',
          statusCode: res.statusCode);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Delete a product; treat 204 and 404 as success
  Future<void> deleteProduct(int id, {String? token}) async {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final uri = Uri.parse('$baseUrl/api/products/$id');

    final res = await _executeWithRetry(
      () => client.delete(uri, headers: headers),
      context: 'deleteProduct',
    );

    if (res.statusCode == 204 || res.statusCode == 200 || res.statusCode == 404)
      return;
    throw ApiConnectionException('Failed to delete product: ${res.statusCode}',
        statusCode: res.statusCode);
  }

  /// Push a batch of changes to /api/sync/push and return parsed response
  Future<Map<String, dynamic>> pushChangesBatch(
      List<Map<String, dynamic>> changes,
      {required String token,
      String? clientId}) async {
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token'
    };
    final uri = Uri.parse('$baseUrl/api/sync/push');
    final body =
        jsonEncode({'client_id': clientId ?? 'mobile', 'changes': changes});

    final res = await _executeWithRetry(
      () => client.post(uri, headers: headers, body: body),
      context: 'pushChangesBatch',
      timeout:
          const Duration(seconds: 30), // Longer timeout for sync operations
    );

    if (res.statusCode != 200) {
      throw ApiConnectionException('Failed to push changes: ${res.statusCode}',
          statusCode: res.statusCode);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Fetch server-side change log (append-only) since `sinceSeq` and return map { 'changes': [...], 'head_seq': n }
  Future<Map<String, dynamic>> fetchChangesSinceSeq(int sinceSeq,
      {required String token, int limit = 500, String? types}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token'
    };

    final q = <String, String>{
      'since_seq': sinceSeq.toString(),
      'limit': limit.toString()
    };
    if (types != null) q['types'] = types;
    final uri =
        Uri.parse('$baseUrl/api/sync/changes').replace(queryParameters: q);

    final res = await _executeWithRetry(
      () => client.get(uri, headers: headers),
      context: 'fetchChangesSinceSeq',
      timeout:
          const Duration(seconds: 30), // Longer timeout for sync operations
    );

    if (res.statusCode != 200) {
      throw ApiConnectionException('Failed to fetch changes: ${res.statusCode}',
          statusCode: res.statusCode);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
