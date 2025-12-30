import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';

class ProductService {
  static const String baseUrl = Env.baseUrl;
  final http.Client _client;

  ProductService({http.Client? client}) : _client = client ?? http.Client();

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  // Normalize store id: treat 0 as global (null)
  int? _normalizeStoreId(int? id) => (id != null && id == 0) ? null : id;

  Future<List<Map<String, dynamic>>> getProducts({int? storeId}) async {
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

    // Debug: log outgoing X-Store-ID header (non-sensitive)
    debugPrint(
        'ProductService.getProducts: X-Store-ID=${headers['X-Store-ID']}');

    final response = await _client.get(
      Uri.parse('$baseUrl/api/products'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => item as Map<String, dynamic>).toList();
    } else {
      throw Exception('Failed to load products');
    }
  }

  Future<List<Map<String, dynamic>>> getAllProducts(
      {bool includeInactive = false, int? storeId}) async {
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

    // Debug: log outgoing X-Store-ID header (non-sensitive)
    debugPrint(
        'ProductService.getAllProducts: X-Store-ID=${headers['X-Store-ID']}');

    final uri =
        Uri.parse('$baseUrl/api/products/all').replace(queryParameters: {
      'include_inactive': includeInactive.toString(),
    });

    final response = await _client.get(
      uri,
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => item as Map<String, dynamic>).toList();
    } else {
      throw Exception('Failed to load products');
    }
  }

  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> productData,
      {int? storeId}) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    // Determine store id to use: parameter takes precedence, otherwise use stored current_store_id
    int? sid = storeId;
    if (sid == null) {
      final prefs = await SharedPreferences.getInstance();
      sid = prefs.getInt('current_store_id');
    }
    sid = _normalizeStoreId(sid);
    if (sid != null) {
      headers['X-Store-ID'] = sid.toString();
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/api/products'),
      headers: headers,
      body: jsonEncode(productData),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      // Include server response body for easier debugging
      debugPrint(
          'ProductService.createProduct: error ${response.statusCode} ${response.body}');
      throw Exception('Failed to create product: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updateProduct(
      int productId, Map<String, dynamic> productData,
      {int? storeId}) async {
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

    final response = await _client.put(
      Uri.parse('$baseUrl/api/products/$productId'),
      headers: headers,
      body: jsonEncode(productData),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update product');
    }
  }

  Future<void> deleteProduct(int productId, {int? storeId}) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final headers = {
      'Authorization': 'Bearer $token',
    };

    storeId = _normalizeStoreId(storeId);
    if (storeId != null) {
      headers['X-Store-ID'] = storeId.toString();
    }

    final response = await _client.delete(
      Uri.parse('$baseUrl/api/products/$productId'),
      headers: headers,
    );

    // Treat 204 as success. If the product was already removed (404), treat it as success too
    // and surface diagnostic info for other statuses to aid debugging.
    if (response.statusCode == 204) {
      return;
    } else if (response.statusCode == 404) {
      debugPrint(
          'ProductService.deleteProduct: 404 Not Found for productId $productId; treating as deleted');
      return;
    } else {
      // Include server response body for easier debugging
      debugPrint(
          'ProductService.deleteProduct: error ${response.statusCode} ${response.body}');
      throw Exception(
          'Failed to delete product: ${response.statusCode} ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updateProductStatus(int productId, bool isActive,
      {int? storeId}) async {
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

    final response = await _client.patch(
      Uri.parse('$baseUrl/api/products/$productId/status'),
      headers: headers,
      body: jsonEncode({'is_active': isActive}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update product status');
    }
  }

  Future<List<Map<String, dynamic>>> getLowStockAlerts({int? storeId}) async {
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

    final response = await http.get(
      Uri.parse('$baseUrl/api/inventory/alerts'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => item as Map<String, dynamic>).toList();
    } else {
      throw Exception('Failed to load low stock alerts');
    }
  }
}
