import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException([this.message = 'Unauthorized']);
  @override
  String toString() => 'UnauthorizedException: $message';
}

class StoreService {
  static const String baseUrl = Env.baseUrl;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<void> _handleUnauthorized() async {
    debugPrint('StoreService: authorization failed — clearing saved token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
  }

  Future<List<Map<String, dynamic>>> getStores() async {
    final token = await _getToken();
    if (token == null) throw UnauthorizedException('Not authenticated');

    debugPrint('StoreService.getStores: calling $baseUrl/api/stores');
    final response = await http.get(
      Uri.parse('$baseUrl/api/stores'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    debugPrint(
        'StoreService.getStores: response status ${response.statusCode}');

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => item as Map<String, dynamic>).toList();
    } else if (response.statusCode == 401) {
      await _handleUnauthorized();
      throw UnauthorizedException(response.body);
    } else {
      debugPrint('StoreService.getStores: error body ${response.body}');
      throw Exception('Failed to load stores: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> getMyStores() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    debugPrint('StoreService.getMyStores: calling $baseUrl/api/stores');
    final response = await http.get(
      Uri.parse('$baseUrl/api/stores'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    debugPrint(
        'StoreService.getMyStores: response status ${response.statusCode}');

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => item as Map<String, dynamic>).toList();
    } else {
      debugPrint('StoreService.getMyStores: error body ${response.body}');
      throw Exception('Failed to load my stores: ${response.statusCode}');
    }
  }

  /// Get available stores for the current user (superadmin -> all active stores, admin -> assigned stores)
  Future<List<Map<String, dynamic>>> getAvailableStores() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    debugPrint(
        'StoreService.getAvailableStores: calling $baseUrl/api/users/me/available-stores');
    final response = await http.get(
      Uri.parse('$baseUrl/api/users/me/available-stores'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    debugPrint(
        'StoreService.getAvailableStores: response status ${response.statusCode}');

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => item as Map<String, dynamic>).toList();
    } else {
      debugPrint(
          'StoreService.getAvailableStores: error body ${response.body}');
      throw Exception(
          'Failed to load available stores: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> switchStore(int storeId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    debugPrint(
        'StoreService.switchStore: POST $baseUrl/api/stores/switch/$storeId');
    final response = await http.post(
      Uri.parse('$baseUrl/api/stores/switch/$storeId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    debugPrint(
        'StoreService.switchStore: response status ${response.statusCode}');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      debugPrint('StoreService.switchStore: error body ${response.body}');
      throw Exception('Failed to switch store: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getCurrentStore() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    debugPrint('StoreService.getCurrentStore: GET $baseUrl/api/stores/current');
    final response = await http.get(
      Uri.parse('$baseUrl/api/stores/current'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    debugPrint(
        'StoreService.getCurrentStore: response status ${response.statusCode}');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 422) {
      // Some backends respond with 422 when no canonical current store is set.
      // Treat this as an explicit 'All Stores' (null current_store) to avoid
      // surfacing exceptions to the UI.
      debugPrint(
          'StoreService.getCurrentStore: status 422 — treating as All Stores');
      return {'current_store': null};
    } else {
      debugPrint('StoreService.getCurrentStore: error body ${response.body}');
      throw Exception('Failed to get current store: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> createStore(
      Map<String, dynamic> storeData) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    debugPrint(
        'StoreService.createStore: POST $baseUrl/api/stores with ${jsonEncode(storeData)}');
    final response = await http.post(
      Uri.parse('$baseUrl/api/stores'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(storeData),
    );
    debugPrint(
        'StoreService.createStore: response status ${response.statusCode}');

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      debugPrint('StoreService.createStore: error body ${response.body}');
      throw Exception(
          'Failed to create store: ${response.statusCode} - ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updateStore(
      int storeId, Map<String, dynamic> storeData) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    debugPrint(
        'StoreService.updateStore: PUT $baseUrl/api/stores/$storeId with ${jsonEncode(storeData)}');
    final response = await http.put(
      Uri.parse('$baseUrl/api/stores/$storeId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(storeData),
    );
    debugPrint(
        'StoreService.updateStore: response status ${response.statusCode}');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      debugPrint('StoreService.updateStore: error body ${response.body}');
      throw Exception(
          'Failed to update store: ${response.statusCode} - ${response.body}');
    }
  }

  Future<void> deleteStore(int storeId) async {
    final token = await _getToken();
    if (token == null) throw UnauthorizedException('Not authenticated');

    // Use hard delete endpoint to remove store and related data permanently
    debugPrint(
        'StoreService.deleteStore: DELETE $baseUrl/api/stores/$storeId/hard');
    final response = await http.delete(
      Uri.parse('$baseUrl/api/stores/$storeId/hard'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    debugPrint(
        'StoreService.deleteStore: response status ${response.statusCode}');

    if (response.statusCode == 200) {
      return;
    } else if (response.statusCode == 401) {
      // Clear saved token and surface a clear exception to the UI so it can redirect
      await _handleUnauthorized();
      debugPrint('StoreService.deleteStore: unauthorized - ${response.body}');
      throw UnauthorizedException(response.body);
    } else {
      debugPrint('StoreService.deleteStore: error body ${response.body}');
      throw Exception(
          'Failed to delete store: ${response.statusCode} - ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> getStoreUsers(int storeId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    debugPrint(
        'StoreService.getStoreUsers: GET $baseUrl/api/stores/$storeId/users');
    final response = await http.get(
      Uri.parse('$baseUrl/api/stores/$storeId/users'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    debugPrint(
        'StoreService.getStoreUsers: response status ${response.statusCode}');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => item as Map<String, dynamic>).toList();
    } else {
      debugPrint('StoreService.getStoreUsers: error body ${response.body}');
      throw Exception('Failed to load store users: ${response.statusCode}');
    }
  }

  Future<void> assignAdminToStore(int storeId, int adminId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    debugPrint(
        'StoreService.assignAdminToStore: POST $baseUrl/api/stores/$storeId/assign-admin?admin_id=$adminId');
    final response = await http.post(
      Uri.parse('$baseUrl/api/stores/$storeId/assign-admin?admin_id=$adminId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    debugPrint(
        'StoreService.assignAdminToStore: response status ${response.statusCode}');

    if (response.statusCode != 200) {
      debugPrint(
          'StoreService.assignAdminToStore: error body ${response.body}');
      throw Exception(
          'Failed to assign admin: ${response.statusCode} - ${response.body}');
    }
  }
}
