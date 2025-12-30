import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/data/sync/postgres_sync_service.dart';
import 'package:mobile/data/remote/postgres_api_service.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../test_utils/fake_http_client.dart';
import '../../test_helpers.dart';

class _FakeConnectivity implements Connectivity {
  @override
  Future<ConnectivityResult> checkConnectivity() async =>
      ConnectivityResult.wifi;

  @override
  Stream<ConnectivityResult> get onConnectivityChanged => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    initSqfliteForTests();
    await DatabaseHelper.initTestDb();
  });

  tearDown(() async {
    await DatabaseHelper.resetTestDb();
  });

  test('batch push applies id_map and marks queue as synced', () async {
    final db = DatabaseHelper();
    final d = await db.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final idA = await d.insert('products', {
      'store_id': 1,
      'name': 'TmpA',
      'sku': 'TA01',
      'price': 1.0,
      'stock_quantity': 4,
      'is_synced': 0,
      'last_updated': now
    });

    final idB = await d.insert('products', {
      'store_id': 1,
      'name': 'TmpB',
      'sku': 'TB01',
      'price': 2.0,
      'stock_quantity': 2,
      'is_synced': 0,
      'last_updated': now
    });

    final payloadA = jsonEncode({
      'table': 'products',
      'row_id': idA,
      'action': 'CREATE',
      'data': {
        'name': 'TmpA',
        'sku': 'TA01',
        'price': 1.0,
        'stock_quantity': 4,
        'store_id': 1
      }
    });

    final payloadB = jsonEncode({
      'table': 'products',
      'row_id': idB,
      'action': 'CREATE',
      'data': {
        'name': 'TmpB',
        'sku': 'TB01',
        'price': 2.0,
        'stock_quantity': 2,
        'store_id': 1
      }
    });

    await d.insert('sync_queue', {
      'table_name': 'products',
      'row_id': idA,
      'action': 'CREATE',
      'payload': payloadA,
      'created_at': now,
      'retry_count': 0,
      'status': 'pending'
    });

    await d.insert('sync_queue', {
      'table_name': 'products',
      'row_id': idB,
      'action': 'CREATE',
      'payload': payloadB,
      'created_at': now,
      'retry_count': 0,
      'status': 'pending'
    });

    final builder = FakeHttpClient();
    builder.when('/api/sync/push', (req) async {
      final body = jsonDecode((req as dynamic).body) as Map<String, dynamic>;
      final changes = (body['changes'] as List).cast<Map<String, dynamic>>();

      // validate we received two changes and return id_map mapping temp ids to server ids
      expect(changes.length, 2);
      final tempIds = changes.map((c) => c['temp_id'] as String).toList();

      return http.Response(
          jsonEncode({
            'applied': [
              {'resource_type': 'product', 'operation': 'create', 'id': 1001},
              {'resource_type': 'product', 'operation': 'create', 'id': 1002}
            ],
            'conflicts': [],
            'id_map': {tempIds[0]: 1001, tempIds[1]: 1002}
          }),
          200,
          headers: {'content-type': 'application/json'});
    });

    final client = builder.build();
    final api = PostgresApiService(client: client);

    final svc = PostgresSyncService(
      db: db,
      api: api,
      httpClient: client,
      connectivity: _FakeConnectivity(),
      secureStorage: FakeFlutterSecureStorage(),
    );

    final ok = await svc.syncPendingChangesBatch();
    expect(ok, isTrue);

    final rowsA = await d.query('products', where: 'id = ?', whereArgs: [idA]);
    final rowsB = await d.query('products', where: 'id = ?', whereArgs: [idB]);

    expect(rowsA.first['server_id'], 1001);
    expect(rowsB.first['server_id'], 1002);

    final qA =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [idA]);
    final qB =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [idB]);

    expect(qA.first['status'], 'synced');
    expect(qB.first['status'], 'synced');
  });
}
