import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../config/env.dart';
import '../data/local/database_helper.dart';

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException([this.message = 'Unauthorized']);
  @override
  String toString() => 'UnauthorizedException: $message';
}

class StoreService {
  static const String baseUrl = Env.baseUrl;
  final DatabaseHelper? _dbHelper;
  final Connectivity _connectivity;

  StoreService({DatabaseHelper? dbHelper, Connectivity? connectivity})
      : _dbHelper = dbHelper ?? DatabaseHelper(),
        _connectivity = connectivity ?? Connectivity();

  Future<bool> _isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<void> _handleUnauthorized() async {
    debugPrint('StoreService: authorization failed — clearing saved token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
  }

  /// Cache stores locally for offline access
  Future<void> _cacheStores(List<Map<String, dynamic>> stores) async {
    if (_dbHelper == null) return;
    try {
      final db = await _dbHelper!.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final store in stores) {
        await db.insert(
          'stores',
          {
            'server_id': store['id'],
            'name': store['name'],
            'location': store['location'],
            'is_active': store['is_active'] == true ? 1 : 0,
            'last_updated': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      debugPrint('Failed to cache stores: $e');
    }
  }

  /// Get stores from local cache
  Future<List<Map<String, dynamic>>> _getOfflineStores() async {
    if (_dbHelper == null) return [];
    try {
      final db = await _dbHelper!.database;
      final rows = await db.query('stores', where: 'is_active = 1');
      return rows
          .map((row) => {
                'id': row['server_id'] ?? row['id'],
                'name': row['name'],
                'location': row['location'],
                'is_active': row['is_active'] == 1,
              })
          .toList();
    } catch (e) {
      debugPrint('Failed to get offline stores: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getStores() async {
    final token = await _getToken();
    if (token == null) throw UnauthorizedException('Not authenticated');

    // Check if online
    if (!await _isOnline()) {
      debugPrint('StoreService.getStores: offline, using cached stores');
      return _getOfflineStores();
    }

    debugPrint('StoreService.getStores: calling $baseUrl/api/stores');
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/stores'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      debugPrint(
          'StoreService.getStores: response status ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final stores =
            data.map((item) => item as Map<String, dynamic>).toList();
        // Cache for offline access
        await _cacheStores(stores);
        return stores;
      } else if (response.statusCode == 401) {
        await _handleUnauthorized();
        throw UnauthorizedException(response.body);
      } else {
        debugPrint('StoreService.getStores: error body ${response.body}');
        throw Exception('Failed to load stores: ${response.statusCode}');
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      // Network error, use cached data
      debugPrint('StoreService.getStores: network error, using cache: $e');
      return _getOfflineStores();
    }
  }

  Future<List<Map<String, dynamic>>> getMyStores() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    // Check if online
    if (!await _isOnline()) {
      debugPrint('StoreService.getMyStores: offline, using cached stores');
      return _getOfflineStores();
    }

    debugPrint(
        'StoreService.getMyStores: calling $baseUrl/api/users/me/available-stores');
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/me/available-stores'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      debugPrint(
          'StoreService.getMyStores: response status ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final stores =
            data.map((item) => item as Map<String, dynamic>).toList();
        await _cacheStores(stores);
        return stores;
      } else {
        debugPrint('StoreService.getMyStores: error body ${response.body}');
        throw Exception('Failed to load my stores: ${response.statusCode}');
      }
    } catch (e) {
      // Network error, use cached data
      debugPrint('StoreService.getMyStores: network error, using cache: $e');
      return _getOfflineStores();
    }
  }

  /// Get available stores for the current user (superadmin -> all active stores, admin -> assigned stores)
  Future<List<Map<String, dynamic>>> getAvailableStores() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    // Check if online
    if (!await _isOnline()) {
      debugPrint(
          'StoreService.getAvailableStores: offline, using cached stores');
      return _getOfflineStores();
    }

    debugPrint(
        'StoreService.getAvailableStores: calling $baseUrl/api/users/me/available-stores');
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/me/available-stores'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      debugPrint(
          'StoreService.getAvailableStores: response status ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final stores =
            data.map((item) => item as Map<String, dynamic>).toList();
        await _cacheStores(stores);
        return stores;
      } else {
        debugPrint(
            'StoreService.getAvailableStores: error body ${response.body}');
        throw Exception(
            'Failed to load available stores: ${response.statusCode}');
      }
    } catch (e) {
      // Network error, use cached data
      debugPrint(
          'StoreService.getAvailableStores: network error, using cache: $e');
      return _getOfflineStores();
    }
  }

  Future<Map<String, dynamic>> switchStore(int storeId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    // If offline, allow local store switch
    if (!await _isOnline()) {
      debugPrint(
          'StoreService.switchStore: offline, switching locally to $storeId');
      // Return a mock response for offline switching
      if (storeId == 0) {
        return {
          'current_store': null,
          'message': 'Switched to All Stores (offline)'
        };
      }
      final stores = await _getOfflineStores();
      final store = stores.firstWhere(
        (s) => s['id'] == storeId,
        orElse: () => {'id': storeId, 'name': 'Unknown Store'},
      );
      return {'current_store': store, 'message': 'Switched store (offline)'};
    }

    debugPrint(
        'StoreService.switchStore: POST $baseUrl/api/stores/switch/$storeId');
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/stores/switch/$storeId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      debugPrint(
          'StoreService.switchStore: response status ${response.statusCode}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        debugPrint('StoreService.switchStore: error body ${response.body}');
        throw Exception('Failed to switch store: ${response.statusCode}');
      }
    } catch (e) {
      // Network error, allow local switch
      debugPrint(
          'StoreService.switchStore: network error, switching locally: $e');
      if (storeId == 0) {
        return {
          'current_store': null,
          'message': 'Switched to All Stores (offline)'
        };
      }
      final stores = await _getOfflineStores();
      final store = stores.firstWhere(
        (s) => s['id'] == storeId,
        orElse: () => {'id': storeId, 'name': 'Unknown Store'},
      );
      return {'current_store': store, 'message': 'Switched store (offline)'};
    }
  }

  Future<Map<String, dynamic>> getCurrentStore() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    // If offline, return from local storage
    if (!await _isOnline()) {
      debugPrint('StoreService.getCurrentStore: offline, using cached store');
      final prefs = await SharedPreferences.getInstance();
      final storedStoreId = prefs.getInt('current_store_id');
      if (storedStoreId == null || storedStoreId == 0) {
        return {'current_store': null};
      }
      final stores = await _getOfflineStores();
      final store = stores.firstWhere(
        (s) => s['id'] == storedStoreId,
        orElse: () => {'id': storedStoreId, 'name': 'Unknown Store'},
      );
      return {'current_store': store};
    }

    debugPrint('StoreService.getCurrentStore: GET $baseUrl/api/stores/current');
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/stores/current'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      debugPrint(
          'StoreService.getCurrentStore: response status ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('StoreService.getCurrentStore: received data=$data');
        return data;
      } else {
        debugPrint(
            'StoreService.getCurrentStore: error ${response.statusCode} body ${response.body}');
        throw Exception('Failed to get current store: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('StoreService.getCurrentStore: network error $e');
      return {'current_store': null};
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
