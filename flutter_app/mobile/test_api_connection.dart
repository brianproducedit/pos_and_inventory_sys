import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'lib/config/env.dart';

void main() async {
  debugPrint('Testing connection to Railway backend...');
  debugPrint('API URL: ${Env.baseUrl}');

  // Test 1: Check /docs endpoint
  debugPrint('\n1. Testing /docs endpoint...');
  try {
    final docsResponse = await http
        .get(
          Uri.parse('${Env.baseUrl}/docs'),
        )
        .timeout(const Duration(seconds: 10));
    debugPrint('   Status: ${docsResponse.statusCode}');
    debugPrint('   ✅ API docs accessible');
  } catch (e) {
    debugPrint('   ❌ Failed: $e');
  }

  // Test 2: Test login endpoint
  debugPrint('\n2. Testing login endpoint...');
  try {
    final loginResponse = await http
        .post(
          Uri.parse('${Env.baseUrl}/auth/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'username=superadmin&password=bk007bang',
        )
        .timeout(const Duration(seconds: 10));

    debugPrint('   Status: ${loginResponse.statusCode}');
    if (loginResponse.statusCode == 200) {
      final data = json.decode(loginResponse.body);
      final token = data['access_token'];
      debugPrint('   ✅ Login successful');
      debugPrint('   Token: ${token.substring(0, 50)}...');

      // Test 3: Get user info with token
      debugPrint('\n3. Testing authenticated endpoint (/api/users/me)...');
      try {
        final meResponse = await http.get(
          Uri.parse('${Env.baseUrl}/api/users/me'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 10));

        debugPrint('   Status: ${meResponse.statusCode}');
        if (meResponse.statusCode == 200) {
          final userData = json.decode(meResponse.body);
          debugPrint('   ✅ User data retrieved');
          debugPrint('   Username: ${userData['username']}');
          debugPrint('   Role: ${userData['role']}');
        } else {
          debugPrint('   ❌ Failed: ${meResponse.body}');
        }
      } catch (e) {
        debugPrint('   ❌ Failed: $e');
      }
    } else {
      debugPrint('   ❌ Login failed: ${loginResponse.body}');
    }
  } catch (e) {
    debugPrint('   ❌ Failed: $e');
  }

  debugPrint('\n✅ API connection tests complete!');
}
