import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';

class AuthService {
  static const String baseUrl = Env.baseUrl;

  // Accept an injectable HTTP client for easier testing.
  final http.Client _client;

  AuthService([http.Client? client]) : _client = client ?? http.Client();

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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', data['access_token']);
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
          throw {
            'code': code,
            'message':
                detail ?? 'Login failed with status ${response.statusCode}'
          };
        }
      } catch (_) {
        // Non-JSON body, fall through to generic fallback
      }

      debugPrint(
          'Login failed with status ${response.statusCode}: ${response.body}');
      throw {'code': response.statusCode, 'message': response.body};
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
          throw {'code': code, 'message': detail ?? 'Failed to get user info'};
        }
      } catch (_) {}
      debugPrint(
          'getUserInfo failed with status ${response.statusCode}: ${response.body}');
      throw {'code': response.statusCode, 'message': 'Failed to get user info'};
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }
}
