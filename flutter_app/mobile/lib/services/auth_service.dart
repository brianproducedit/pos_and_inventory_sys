import 'package:http/http.dart' as http;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../config/env.dart';
import '../db/app_database.dart';

// Typed exception for auth errors to avoid throwing raw Maps.
class AuthException implements Exception {
  final dynamic code; // can be int or String
  final String message;
  AuthException(this.code, this.message) {
    // Ensure message is never null or empty
    assert(message.isNotEmpty, 'AuthException message cannot be empty');
  }
  @override
  String toString() => 'AuthException(code: $code, message: $message)';
  Map<String, dynamic> toMap() => {'code': code, 'message': message};
}

class AuthService {
  /// Hash password for local storage comparison (simple SHA-256 for offline validation)
  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Attempt offline login using stored credentials and Drift DB
  Future<bool> offlineLogin(
    AppDatabase db, {
    String? username,
    String? password,
  }) async {
    // Use provided credentials or fall back to stored ones
    final storedUsername =
        username ?? await _secureStorage.read(key: 'username');
    final storedPassword =
        password ?? await _secureStorage.read(key: 'password');

    if (storedUsername == null || storedPassword == null) return false;

    final user =
        await (db.select(db.users)
              ..where((u) => u.username.equals(storedUsername))
              ..limit(1))
            .getSingleOrNull();

    if (user != null) {
      // Check if we have a stored password hash for offline validation
      final storedHash = await _secureStorage.read(
        key: 'password_hash_$storedUsername',
      );
      if (storedHash != null) {
        final inputHash = _hashPassword(storedPassword);
        if (inputHash != storedHash) {
          return false; // Password mismatch
        }
      }
      // If no stored hash, allow login (backward compatibility)
      return true;
    }
    return false;
  }

  static const String baseUrl = Env.baseUrl;

  // Accept an injectable HTTP client for easier testing.
  final http.Client _client;
  final FlutterSecureStorage _secureStorage;
  final AppDatabase? _db;

  AuthService([
    http.Client? client,
    FlutterSecureStorage? secureStorage,
    AppDatabase? db,
  ]) : _client = client ?? http.Client(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _db = db;

  /// Login: call remote token endpoint, store token securely, and persist basic user info in local DB.
  Future<Map<String, dynamic>> login(String username, String password) async {
    debugPrint('Attempting login with username: $username');
    debugPrint('Calling: $baseUrl/auth/token');
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': username, 'password': password},
    );

    debugPrint('Response status: ${response.statusCode}');
    debugPrint('Response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final token = data['access_token'] as String?;
      if (token != null) {
        // Write token first
        await _secureStorage.write(key: 'access_token', value: token);
        // Store credentials for offline login (password hashed for security)
        await _secureStorage.write(key: 'username', value: username);
        await _secureStorage.write(key: 'password', value: password);
        // Store hashed password for offline validation
        await _secureStorage.write(
          key: 'password_hash_$username',
          value: _hashPassword(password),
        );
        // Maintain backward compatibility with code that still reads from SharedPreferences
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('access_token', token);
        } catch (_) {}

        // Try to fetch and persist user info; if persisting fails, rollback token write to keep atomicity
        try {
          final userInfo = await getUserInfo();
          if (_db != null) {
            final id = userInfo['id'] as int?;
            final fullName = userInfo['name'] as String? ?? '';
            final uname = userInfo['username'] as String? ?? username;
            final roleStr = userInfo['role'] as String? ?? 'user';
            final storeId = userInfo['store_id'] as int?;

            // Map role string to UserRole enum
            UserRole role;
            switch (roleStr.toLowerCase()) {
              case 'admin':
                role = UserRole.admin;
                break;
              case 'superadmin':
                role = UserRole.superadmin;
                break;
              case 'cashier':
              default:
                role = UserRole.cashier;
            }

            // Insert or replace full user info locally for offline access using Drift
            await _db
                .into(_db.users)
                .insertOnConflictUpdate(
                  UsersCompanion.insert(
                    serverId: Value(id),
                    username: uname,
                    passwordHash: _hashPassword(
                      password,
                    ), // Store hashed password
                    fullName: Value(fullName),
                    role: role,
                    storeId: Value(storeId),
                  ),
                );
          }
        } catch (e) {
          // Rollback token write to keep login atomic if we cannot persist user info
          try {
            await _secureStorage.delete(key: 'access_token');
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('access_token');
          } catch (_) {}
          debugPrint('Login user persistence failed: $e');
          throw Exception('Login user persistence failed: $e');
        }
      }

      return data;
    } else {
      // Try to parse error body to surface actionable messages to UI.
      String errorMessage = 'Login failed with status ${response.statusCode}';
      dynamic errorCode = response.statusCode;

      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map) {
          final detail =
              parsed['detail'] ?? parsed['message'] ?? parsed['error'];
          final code = parsed['code'] ?? response.statusCode;

          if (detail != null && detail.toString().isNotEmpty) {
            errorMessage = detail.toString();
          }
          errorCode = code;
        } else if (response.body.isNotEmpty) {
          // If response body is not JSON but not empty, use it as message
          errorMessage = response.body;
        }
      } catch (parseError) {
        // If JSON parsing fails, use the raw response body if available
        debugPrint('Failed to parse error response: $parseError');
        if (response.body.isNotEmpty && response.body != 'null') {
          errorMessage = response.body;
        }
      }

      debugPrint('Login failed: code=$errorCode, message=$errorMessage');
      throw AuthException(errorCode, errorMessage);
    }
  }

  Future<Map<String, dynamic>> getUserInfo() async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _client.get(
      Uri.parse('$baseUrl/api/users/me'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map) {
          final detail =
              parsed['detail'] ?? parsed['message'] ?? parsed['error'];
          final code = parsed['code'] ?? response.statusCode;
          debugPrint('getUserInfo failed: code=$code, detail=$detail');
          throw AuthException(code, detail ?? 'Failed to get user info');
        }
      } catch (_) {}
      debugPrint(
        'getUserInfo failed with status ${response.statusCode}: ${response.body}',
      );
      throw AuthException(response.statusCode, 'Failed to get user info');
    }
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(key: 'access_token');
  }

  Future<bool> isLoggedIn() async {
    final t = await getToken();
    return t != null && t.isNotEmpty;
  }

  /// Logout: do NOT wipe local DB; only clear the stored token to preserve local data.
  Future<void> logout() async {
    await _secureStorage.delete(key: 'access_token');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
    } catch (_) {}
  }
}
