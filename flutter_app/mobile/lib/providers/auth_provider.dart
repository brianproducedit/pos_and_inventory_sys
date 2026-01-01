import 'dart:async';

import 'package:flutter/material.dart';
import '../db/app_database.dart';
import '../services/offline_auth_service.dart';
import '../data/remote/api_client.dart';

class AuthProvider with ChangeNotifier {
  final OfflineAuthService _offlineAuthService;
  User? _user;
  bool _isAuthenticated = false;

  User? get user => _user;
  bool get isAuthenticated => _isAuthenticated;

  // Convenience getters
  int? get userId => _user?.id;
  int? get storeId => _user?.storeId;
  String? get username => _user?.username;
  UserRole? get role => _user?.role;
  String? get roleString => _user?.role.name;

  AuthProvider({
    required AppDatabase db,
    required ApiClient apiClient,
  }) : _offlineAuthService = OfflineAuthService(
          db: db,
          apiClient: apiClient,
        );

  /// Login with username and password (offline-first)
  Future<void> login(String username, String password) async {
    try {
      final result = await _offlineAuthService.login(username, password);

      if (result.success && result.user != null) {
        _user = result.user;
        _isAuthenticated = true;
        notifyListeners();
        debugPrint(
            'Login successful for user: $username (${result.user!.role.name})');
      } else {
        throw AuthException(
          'login_failed',
          result.message ?? 'Login failed',
        );
      }
    } catch (e) {
      debugPrint('Login error: $e');
      rethrow;
    }
  }

  /// Create a ghost user (offline user creation)
  Future<User> createGhostUser({
    required String username,
    required String password,
    required String fullName,
    required UserRole role,
    int? storeId,
  }) async {
    final result = await _offlineAuthService.createGhostUser(
      username: username,
      password: password,
      fullName: fullName,
      role: role,
      storeId: storeId,
    );

    if (!result.success || result.user == null) {
      throw AuthException(
        'create_user_failed',
        result.message ?? 'Failed to create user',
      );
    }

    return result.user!;
  }

  /// Change password for current user
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (_user == null) {
      throw AuthException('not_authenticated', 'No user is logged in');
    }

    final result = await _offlineAuthService.changePassword(
      userId: _user!.id,
      oldPassword: oldPassword,
      newPassword: newPassword,
    );

    if (result.success && result.user != null) {
      _user = result.user;
      notifyListeners();
    } else {
      throw AuthException(
        'change_password_failed',
        result.message ?? 'Failed to change password',
      );
    }
  }

  /// Logout
  Future<void> logout() async {
    await _offlineAuthService.logout();
    _user = null;
    _isAuthenticated = false;
    notifyListeners();
  }

  /// Check authentication status on app start
  Future<void> checkAuthStatus() async {
    try {
      final currentUser = await _offlineAuthService.getCurrentUser();
      if (currentUser != null) {
        _user = currentUser;
        _isAuthenticated = true;
        notifyListeners();
        debugPrint('Restored session for user: ${currentUser.username}');
      }
    } catch (e) {
      debugPrint('Failed to restore session: $e');
    }
  }

  /// Get access token (for API calls)
  Future<String?> getToken() async {
    return await _offlineAuthService.secureStorage.read(key: 'access_token');
  }
}

/// Authentication exception
class AuthException implements Exception {
  final String code;
  final String message;

  AuthException(this.code, this.message);

  @override
  String toString() => 'AuthException($code): $message';
}
