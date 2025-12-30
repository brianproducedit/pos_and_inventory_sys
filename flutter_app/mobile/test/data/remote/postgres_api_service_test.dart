import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/data/remote/postgres_api_service.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../test_utils/fake_http_client.dart';
import '../../test_helpers.dart';

class _FakeClient extends http.BaseClient {
  final Map<String, dynamic> response;
  _FakeClient(this.response);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode(response['products'] ?? []);
    final bytes = utf8.encode(body);
    final stream = Stream.fromIterable([bytes]);
    return http.StreamedResponse(stream, 200,
        contentLength: bytes.length,
        headers: {'content-type': 'application/json'});
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PostgresApiService', () {
    setUp(() async {
      initSqfliteForTests();
      await DatabaseHelper.initTestDb();
    });

    tearDown(() async {
      await DatabaseHelper.resetTestDb();
    });

    test('fetchInitialDataAndSeedDB inserts products into empty DB', () async {
      final fakeProducts = [
        {
          'id': 101,
          'store_id': 1,
          'name': 'P1',
          'sku': 'P1',
          'price': 1.0,
          'stock_quantity': 5
        }
      ];
      final client = _FakeClient({'products': fakeProducts});
      final svc = PostgresApiService(client: client);
      final db = DatabaseHelper();

      await svc.fetchInitialDataAndSeedDB(token: 'tok', dbHelper: db);

      final rows = (await db.database).query('products');
      expect((await rows).length, 1);
    });

    test('fetchProducts returns products list', () async {
      final builder = FakeHttpClient();
      builder.when('/api/products', (req) async {
        return http.Response(
            jsonEncode([
              {'id': 201, 'name': 'ProdA', 'price': 3.5, 'stock_quantity': 7}
            ]),
            200,
            headers: {'content-type': 'application/json'});
      });
      final client = builder.build();
      final svc = PostgresApiService(client: client);

      final prods = await svc.fetchProducts();
      expect(prods, isNotEmpty);
      expect(prods.first['name'], 'ProdA');
    });

    test('create/update/delete product flow', () async {
      final builder = FakeHttpClient();
      builder.when('/api/products', (req) async {
        // creation returns created object
        final body = jsonDecode((req as dynamic).body) as Map<String, dynamic>;
        return http.Response(jsonEncode({...body, 'id': 301}), 201,
            headers: {'content-type': 'application/json'});
      });
      builder.when(RegExp(r'/api/products/\d+'), (req) async {
        final path = (req.url.path as String);
        final id = int.parse(path.split('/').last);
        if (req.method == 'PUT') {
          final body =
              jsonDecode((req as dynamic).body) as Map<String, dynamic>;
          return http.Response(jsonEncode({...body, 'id': id}), 200,
              headers: {'content-type': 'application/json'});
        }
        if (req.method == 'DELETE') {
          return http.Response('', 204);
        }
        return http.Response('Not found', 404);
      });

      final client = builder.build();
      final svc = PostgresApiService(client: client);

      final created = await svc.createProduct({'name': 'New', 'price': 2.5});
      expect(created['id'], 301);

      final updated = await svc.updateProduct(301, {'price': 4.0});
      expect(updated['price'], 4.0);

      await svc.deleteProduct(301); // should not throw
    });

    test('fetchInitialDataAndSeedDB merges existing product by server_id',
        () async {
      final initial = {
        'server_id': 201,
        'store_id': 1,
        'name': 'OldName',
        'sku': 'OLD',
        'price': 2.0,
        'stock_quantity': 3,
        'is_synced': 1,
        'last_updated': DateTime.now().millisecondsSinceEpoch
      };
      final db = DatabaseHelper();
      final d = await db.database;
      await d.insert('products', initial);

      final fakeProducts = [
        {
          'id': 201,
          'store_id': 1,
          'name': 'NewName',
          'sku': 'NEW',
          'price': 2.5,
          'stock_quantity': 10
        }
      ];
      final client = _FakeClient({'products': fakeProducts});
      final svc = PostgresApiService(client: client);

      await svc.fetchInitialDataAndSeedDB(token: 'tok', dbHelper: db);

      final rows = await (await db.database)
          .query('products', where: 'server_id = ?', whereArgs: [201]);
      expect(rows.length, 1);
      expect(rows.first['name'], 'NewName');
      expect(rows.first['price'], 2.5);
    });
  });
}
