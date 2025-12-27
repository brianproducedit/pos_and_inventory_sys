// import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/services/product_service.dart';

void main() {
  setUp(() async {
    // Provide a fake token in SharedPreferences
    SharedPreferences.setMockInitialValues({'access_token': 'fake'});
  });

  test('deleteProduct treats 204 as success', () async {
    final mockClient = MockClient((req) async {
      return http.Response('', 204);
    });

    final svc = ProductService(client: mockClient);

    await svc.deleteProduct(1); // should not throw
  });

  test('deleteProduct treats 404 as success', () async {
    final mockClient = MockClient((req) async {
      return http.Response('Not Found', 404);
    });

    final svc = ProductService(client: mockClient);

    await svc.deleteProduct(2); // should not throw
  });

  test('deleteProduct throws for other non-204 statuses', () async {
    final mockClient = MockClient((req) async {
      return http.Response('Server Error', 500);
    });

    final svc = ProductService(client: mockClient);

    expect(() async => await svc.deleteProduct(3), throwsA(isA<Exception>()));
  });
}
