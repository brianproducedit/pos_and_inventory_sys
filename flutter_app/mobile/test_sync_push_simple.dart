import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  const baseUrl = 'https://backend-production-5388.up.railway.app';

  print('Testing sync push functionality...');
  print('API URL: $baseUrl');

  // Test 1: Login
  print('\n1. Testing login...');
  try {
    final loginResponse = await http
        .post(
          Uri.parse('$baseUrl/auth/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'username=superadmin&password=bk007bang',
        )
        .timeout(const Duration(seconds: 10));

    print('   Status: ${loginResponse.statusCode}');
    if (loginResponse.statusCode == 200) {
      final data = json.decode(loginResponse.body);
      final token = data['access_token'];
      print('   ✅ Login successful');

      // Test 2: Get stores to find a store ID
      print('\n2. Getting stores...');
      try {
        final storesResponse = await http.get(
          Uri.parse('$baseUrl/api/stores'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 10));

        print('   Status: ${storesResponse.statusCode}');
        if (storesResponse.statusCode == 200) {
          final stores = json.decode(storesResponse.body);
          print('   ✅ Found ${stores.length} stores');
          if (stores.isNotEmpty) {
            final storeId = stores[0]['id'];
            print('   Using store ID: $storeId');

            // Test 3: Test sync push with product creation
            print('\n3. Testing sync push with product creation...');
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
                    Uri.parse('$baseUrl/api/sync/push'),
                    headers: {
                      'Content-Type': 'application/json',
                      'Authorization': 'Bearer $token'
                    },
                    body: json.encode(syncPayload),
                  )
                  .timeout(const Duration(seconds: 15));

              print('   Sync push status: ${syncResponse.statusCode}');
              if (syncResponse.statusCode == 200) {
                final result = json.decode(syncResponse.body);
                print('   ✅ Sync push successful!');
                print('   Applied: ${result['applied']}');
                print('   ID Map: ${result['id_map']}');
              } else {
                print('   ❌ Sync push failed: ${syncResponse.body}');
              }
            } catch (e) {
              print('   ❌ Sync push error: $e');
            }
          }
        } else {
          print('   ❌ Failed to get stores: ${storesResponse.body}');
        }
      } catch (e) {
        print('   ❌ Failed to get stores: $e');
      }
    } else {
      print('   ❌ Login failed: ${loginResponse.body}');
    }
  } catch (e) {
    print('   ❌ Login error: $e');
  }

  print('\n✅ Sync push tests complete!');
}
