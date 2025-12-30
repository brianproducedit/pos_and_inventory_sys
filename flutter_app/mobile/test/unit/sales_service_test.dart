import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../test_utils/fake_http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_helpers.dart';
import 'dart:io';
import 'package:mobile/services/sales_service.dart';

void main() {
  setUp(() async {
    initializeTestHelpersOnce();
  });

  test('createSale sends X-Store-ID when explicit storeId provided', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'fake'});

    final builder = FakeHttpClient();
    builder.when('/api/sales', (req) async {
      expect(req.headers['x-store-id'], '42');
      return http.Response('{}', 200);
    });

    final svc = SalesService(client: builder.build());

    await svc.createSale({'items': []}, storeId: 42);
  });

  test(
      'createSale falls back to persisted current_store_id when storeId omitted',
      () async {
    SharedPreferences.setMockInitialValues(
        {'access_token': 'fake', 'current_store_id': 88});

    final builder = FakeHttpClient();
    builder.when('/api/sales', (req) async {
      expect(req.headers['x-store-id'], '88');
      return http.Response('{}', 200);
    });

    final svc = SalesService(client: builder.build());

    await svc.createSale({'items': []});
  });

  test('getReceipt sends X-Store-ID when explicit storeId provided', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'fake'});

    final builder = FakeHttpClient();
    builder.when(RegExp(r'/api/receipts/\d+$'), (req) async {
      expect(req.headers['x-store-id'], '7');
      return http.Response('{}', 200);
    });

    final svc = SalesService(client: builder.build());

    await svc.getReceipt(123, storeId: 7);
  });

  test('getReceipt falls back to persisted current_store_id when omitted',
      () async {
    SharedPreferences.setMockInitialValues(
        {'access_token': 'fake', 'current_store_id': 13});

    final builder = FakeHttpClient();
    builder.when(RegExp(r'/api/receipts/\d+$'), (req) async {
      expect(req.headers['x-store-id'], '13');
      return http.Response('{}', 200);
    });

    final svc = SalesService(client: builder.build());

    await svc.getReceipt(123);
  });

  test(
      'getSales sends X-Store-ID and store_id query when explicit storeId provided',
      () async {
    SharedPreferences.setMockInitialValues({'access_token': 'fake'});

    final builder = FakeHttpClient();
    builder.when('/api/sales', (req) async {
      expect(req.headers['x-store-id'], '55');
      expect(req.url.queryParameters['store_id'], '55');
      return http.Response('[]', 200);
    });

    final svc = SalesService(client: builder.build());

    await svc.getSales(storeId: 55);
  });

  test('getSales treats storeId=0 as global and does not send X-Store-ID',
      () async {
    SharedPreferences.setMockInitialValues({'access_token': 'fake'});

    final builder = FakeHttpClient();
    builder.when('/api/sales', (req) async {
      expect(req.headers['x-store-id'], isNull);
      expect(req.url.queryParameters['store_id'], isNull);
      return http.Response('[]', 200);
    });

    final svc = SalesService(client: builder.build());

    await svc.getSales(storeId: 0);
  });

  test(
      'getSalesAnalytics retries on transient HttpException and eventually throws',
      () async {
    SharedPreferences.setMockInitialValues({'access_token': 'fake'});

    final builder = FakeHttpClient();
    var calls = 0;
    builder.when('/api/analytics/sales', (req) async {
      calls++;
      if (calls < 3) {
        throw HttpException(
            'Connection closed before full header was received');
      }
      return http.Response('{}', 200);
    });

    final svc = SalesService(client: builder.build());

    final res = await svc.getSalesAnalytics();
    expect(res, isA<Map<String, dynamic>>());
    expect(calls, equals(3));
  });

  test('getSales does not send X-Store-ID when omitted and no persisted store',
      () async {
    SharedPreferences.setMockInitialValues({'access_token': 'fake'});

    final builder = FakeHttpClient();
    builder.when('/api/sales', (req) async {
      expect(req.headers['x-store-id'], isNull);
      return http.Response('[]', 200);
    });

    final svc = SalesService(client: builder.build());

    await svc.getSales();
  });
}
