// import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_helpers.dart';
import '../test_utils/fake_http_client.dart';
import 'package:mobile/services/product_service.dart';

void main() {
  setUp(() async {
    // Initialize test helpers (bindings, mock prefs, http overrides)
    initializeTestHelpersOnce();
    // Provide a fake token in SharedPreferences
    SharedPreferences.setMockInitialValues({'access_token': 'fake'});
  });

  test('deleteProduct treats 204 as success', () async {
    final builder = FakeHttpClient();
    builder.when('/api/products/1', (req) async {
      return http.Response('', 204);
    });
    final mockClient = builder.build();

    final svc = ProductService(client: mockClient);

    await svc.deleteProduct(1); // should not throw
  });

  test('deleteProduct treats 404 as success', () async {
    final builder = FakeHttpClient();
    builder.when('/api/products/2', (req) async {
      return http.Response('Not Found', 404);
    });
    final mockClient = builder.build();

    final svc = ProductService(client: mockClient);

    await svc.deleteProduct(2); // should not throw
  });

  test('deleteProduct throws for other non-204 statuses', () async {
    final builder = FakeHttpClient();
    builder.when('/api/products/3', (req) async {
      return http.Response('Server Error', 500);
    });
    final mockClient = builder.build();

    final svc = ProductService(client: mockClient);

    expect(() async => await svc.deleteProduct(3), throwsA(isA<Exception>()));
  });

  test('getProducts treats storeId=0 as global and does not send X-Store-ID',
      () async {
    final builder = FakeHttpClient();
    builder.when('/api/products', (req) async {
      expect(req.headers['x-store-id'], isNull);
      return http.Response('[]', 200);
    });

    final svc = ProductService(client: builder.build());

    await svc.getProducts(storeId: 0);
  });

  test(
      'createProduct falls back to persisted current_store_id=0 and does not send X-Store-ID',
      () async {
    SharedPreferences.setMockInitialValues(
        {'access_token': 'fake', 'current_store_id': 0});
    final builder = FakeHttpClient();
    builder.when('/api/products', (req) async {
      expect(req.headers['x-store-id'], isNull);
      return http.Response('{}', 201);
    });

    final svc = ProductService(client: builder.build());

    await svc.createProduct({'name': 'X'});
  });

  test('deleteProduct does not send X-Store-ID when storeId=0', () async {
    final builder = FakeHttpClient();
    builder.when('/api/products/1', (req) async {
      expect(req.headers['x-store-id'], isNull);
      return http.Response('', 204);
    });
    final mockClient = builder.build();

    final svc = ProductService(client: mockClient);

    await svc.deleteProduct(1, storeId: 0);
  });
}
