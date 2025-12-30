import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../config/env.dart';
import '../data/local/database_helper.dart';

// Typed exception for auth errors to avoid throwing raw Maps.
class AuthException implements Exception {
  final dynamic code; // can be int or String
  final String message;
  AuthException(this.code, this.message);
  @override
  String toString() => 'AuthException(code: $code, message: $message)';
  Map<String, dynamic> toMap() => {'code': code, 'message': message};
}

class AuthService {
  static const String baseUrl = Env.baseUrl;

  // Accept an injectable HTTP client for easier testing.
  final http.Client _client;
  final FlutterSecureStorage _secureStorage;
  final DatabaseHelper? _dbHelper;

  AuthService(
      [http.Client? client,
      FlutterSecureStorage? secureStorage,
      DatabaseHelper? dbHelper])
      : _client = client ?? http.Client(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _dbHelper = dbHelper;

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
        // Maintain backward compatibility with code that still reads from SharedPreferences
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('access_token', token);
        } catch (_) {}

        // Try to fetch and persist user info; if persisting fails, rollback token write to keep atomicity
        try {
          final userInfo = await getUserInfo();
          if (_dbHelper != null && userInfo is Map<String, dynamic>) {
            final id = userInfo['id'] as int?;
            final name = userInfo['name'] as String? ?? '';
            final email = userInfo['email'] as String? ?? '';
            final now = DateTime.now().millisecondsSinceEpoch;
            final db = await _dbHelper!.database;
            // Insert or replace basic user info locally
            await db.insert(
                'users',
                {
                  'server_id': id,
                  'name': name,
                  'email': email,
                  'last_synced': now
                },
                conflictAlgorithm: ConflictAlgorithm.replace);
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
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map) {
          final detail =
              parsed['detail'] ?? parsed['message'] ?? parsed['error'];
          final code = parsed['code'] ?? response.statusCode;
          debugPrint('Login failed: code=$code, detail=$detail');
          throw AuthException(code,
              detail ?? 'Login failed with status ${response.statusCode}');
        }
      } catch (_) {
        // Non-JSON body, fall through to generic fallback
      }

      debugPrint(
          'Login failed with status ${response.statusCode}: ${response.body}');
      throw AuthException(response.statusCode, response.body);
    }
  }

  Future<Map<String, dynamic>> getUserInfo() async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _client.get(
      Uri.parse('$baseUrl/api/users/me'),
      headers: {
        'Authorization': 'Bearer $token',
      },
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
          'getUserInfo failed with status ${response.statusCode}: ${response.body}');
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
