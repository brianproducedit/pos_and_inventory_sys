import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile/models/database_models.dart';
import 'package:mobile/services/auth_service.dart';
import '../data/local/database_helper.dart';
import '../data/remote/postgres_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isAuthenticated = false;
  String? _role;

  User? get user => _user;
  bool get isAuthenticated => _isAuthenticated;
  String? get role => _role;

  // Convenience getters
  int? get storeId => _user?.storeId;
  String? get username => _user?.username;

  Future<String?> getToken() async {
    return await _authService.getToken();
  }

  Future<void> _seedLocalDbIfNeeded() async {
    try {
      final token = await _authService.getToken();
      if (token == null) return;

      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      // Query a single row to avoid expensive counts on large DBs; if less than
      // threshold rows exist we'll trigger the full seed.
      final rows =
          await db.query('products', limit: _localProductSeedThreshold);
      if (rows.length >= _localProductSeedThreshold) {
        // DB already seeded sufficiently
        return;
      }

      // Attempt to fetch initial data and seed DB; non-fatal so we catch errors
      try {
        final api = PostgresApiService();
        await api.fetchInitialDataAndSeedDB(token: token, dbHelper: dbHelper);
        debugPrint('AuthProvider: initial DB seed completed');
      } catch (e) {
        debugPrint('AuthProvider: initial DB seed failed: $e');
      }
    } catch (e) {
      debugPrint('AuthProvider: seedLocalDb check failed: $e');
    }
  }

  final AuthService _authService = AuthService();

  // Threshold under which we consider the local DB "sparse" and attempt an initial seed
  static const int _localProductSeedThreshold = 10;

  Future<void> login(String username, String password) async {
    await _authService.login(username, password);
    // Assume data has user info, but for now, fetch from /users/me
    await _fetchUserInfo();
    _isAuthenticated = true;
    notifyListeners();

    // Fire-and-forget: ensure local DB seeding occurs when a freshly-logged-in
    // device appears to have a sparse products table. This helps devices that
    // missed initial seeding to fetch the canonical product catalog.
    unawaited(_seedLocalDbIfNeeded());
  }

  Future<void> _fetchUserInfo() async {
    final userData = await _authService.getUserInfo();
    // Normalize role to lowercase trimmed string to avoid mismatches
    final rawRole = userData['role']?.toString() ?? '';
    final normalizedRole = rawRole.toLowerCase().trim();

    _user = User(
      id: userData['id'],
      username: userData['username'],
      passwordHash: userData['password_hash'] ?? '',
      role: normalizedRole,
      storeId: userData['store_id'],
      createdAt: DateTime.parse(userData['created_at']),
      updatedAt: DateTime.parse(userData['updated_at']),
    );
    _role = normalizedRole;
    // Store normalized role in prefs
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', _role!);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('user_role');
    _user = null;
    _isAuthenticated = false;
    _role = null;
    notifyListeners();
  }

  Future<void> checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final role = prefs.getString('user_role');
    if (token != null && role != null) {
      // Use stored role immediately to avoid UI flashing incorrect options
      _role = role.toLowerCase().trim();
      _isAuthenticated = true;
      notifyListeners();
      try {
        // Fetch fresh user data to ensure we have the complete user object
        await _fetchUserInfo();
        _isAuthenticated = true;
        notifyListeners();
      } catch (e) {
        // If fetching user info fails, clear stored data
        await logout();
      }
    }
  }
}
