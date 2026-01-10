import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'lib/config/env.dart';

void main() async {
  debugPrint('Testing sync push functionality...');
  debugPrint('API URL: ${Env.baseUrl}');

  // Test 1: Login
  debugPrint('\n1. Testing login...');
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

      // Test 2: Get stores to find a store ID
      debugPrint('\n2. Getting stores...');
      try {
        final storesResponse = await http.get(
          Uri.parse('${Env.baseUrl}/api/stores'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 10));

        debugPrint('   Status: ${storesResponse.statusCode}');
        if (storesResponse.statusCode == 200) {
          final stores = json.decode(storesResponse.body);
          debugPrint('   ✅ Found ${stores.length} stores');
          if (stores.isNotEmpty) {
            final storeId = stores[0]['id'];
            debugPrint('   Using store ID: $storeId');

            // Test 3: Test sync push with product creation
            debugPrint('\n3. Testing sync push with product creation...');
            final syncPayload = {
              "client_id": "test_flutter_client",
              "changes": [
                {
                  "resource_type": "product",
                  "operation": "create",
                  "temp_id": "temp_product_test_123",
                  "data": {
                    "name": "Test Product from Flutter",
                    "description": "Testing sync push from Flutter app",
                    "price": 25.99,
                    "stock_quantity": 75,
                    "is_active": true,
                    "store_id": storeId
                  }
                }
              ]
            };

            try {
              final syncResponse = await http
                  .post(
                    Uri.parse('${Env.baseUrl}/api/sync/push'),
                    headers: {
                      'Content-Type': 'application/json',
                      'Authorization': 'Bearer $token'
                    },
                    body: json.encode(syncPayload),
                  )
                  .timeout(const Duration(seconds: 15));

              debugPrint('   Sync push status: ${syncResponse.statusCode}');
              if (syncResponse.statusCode == 200) {
                final result = json.decode(syncResponse.body);
                debugPrint('   ✅ Sync push successful!');
                debugPrint('   Applied: ${result['applied']}');
                debugPrint('   ID Map: ${result['id_map']}');
              } else {
                debugPrint('   ❌ Sync push failed: ${syncResponse.body}');
              }
            } catch (e) {
              debugPrint('   ❌ Sync push error: $e');
            }
          }
        } else {
          debugPrint('   ❌ Failed to get stores: ${storesResponse.body}');
        }
      } catch (e) {
        debugPrint('   ❌ Failed to get stores: $e');
      }
    } else {
      debugPrint('   ❌ Login failed: ${loginResponse.body}');
    }
  } catch (e) {
    debugPrint('   ❌ Login error: $e');
  }

  debugPrint('\n✅ Sync push tests complete!');
}
