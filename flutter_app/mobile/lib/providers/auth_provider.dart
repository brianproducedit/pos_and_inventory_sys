import 'package:flutter/material.dart';
import 'package:mobile/models/database_models.dart';
import 'package:mobile/services/auth_service.dart';
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

  final AuthService _authService = AuthService();

  Future<void> login(String username, String password) async {
    await _authService.login(username, password);
    // Assume data has user info, but for now, fetch from /users/me
    await _fetchUserInfo();
    _isAuthenticated = true;
    notifyListeners();
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
