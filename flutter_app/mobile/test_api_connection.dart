import 'package:http/http.dart' as http;
import 'dart:convert';
import 'lib/config/env.dart';

void main() async {
  print('Testing connection to Railway backend...');
  print('API URL: ${Env.baseUrl}');

  // Test 1: Check /docs endpoint
  print('\n1. Testing /docs endpoint...');
  try {
    final docsResponse = await http
        .get(
          Uri.parse('${Env.baseUrl}/docs'),
        )
        .timeout(Duration(seconds: 10));
    print('   Status: ${docsResponse.statusCode}');
    print('   ✅ API docs accessible');
  } catch (e) {
    print('   ❌ Failed: $e');
  }

  // Test 2: Test login endpoint
  print('\n2. Testing login endpoint...');
  try {
    final loginResponse = await http
        .post(
          Uri.parse('${Env.baseUrl}/auth/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'username=superadmin&password=bk007bang',
        )
        .timeout(Duration(seconds: 10));

    print('   Status: ${loginResponse.statusCode}');
    if (loginResponse.statusCode == 200) {
      final data = json.decode(loginResponse.body);
      final token = data['access_token'];
      print('   ✅ Login successful');
      print('   Token: ${token.substring(0, 50)}...');

      // Test 3: Get user info with token
      print('\n3. Testing authenticated endpoint (/api/users/me)...');
      try {
        final meResponse = await http.get(
          Uri.parse('${Env.baseUrl}/api/users/me'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(Duration(seconds: 10));

        print('   Status: ${meResponse.statusCode}');
        if (meResponse.statusCode == 200) {
          final userData = json.decode(meResponse.body);
          print('   ✅ User data retrieved');
          print('   Username: ${userData['username']}');
          print('   Role: ${userData['role']}');
        } else {
          print('   ❌ Failed: ${meResponse.body}');
        }
      } catch (e) {
        print('   ❌ Failed: $e');
      }
    } else {
      print('   ❌ Login failed: ${loginResponse.body}');
    }
  } catch (e) {
    print('   ❌ Failed: $e');
  }

  print('\n✅ API connection tests complete!');
}
