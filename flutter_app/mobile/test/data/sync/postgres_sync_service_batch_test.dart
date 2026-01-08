import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile/data/sync/postgres_sync_service.dart';
import 'package:mobile/data/remote/postgres_api_service.dart';
import 'package:mobile/data/sync/sync_database_helper.dart';
import 'package:mobile/data/repositories/sync_repository.dart';
import 'package:mobile/db/app_database.dart';
import '../../test_utils/fake_http_client.dart';

class _FakeConnectivity implements Connectivity {
  @override
  Future<ConnectivityResult> checkConnectivity() async =>
      ConnectivityResult.wifi;

  @override
  Stream<ConnectivityResult> get onConnectivityChanged => const Stream.empty();
}

class TestSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    required String key,
    required String? value,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    required String key,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async =>
      _store[key];

  @override
  Future<void> delete({
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    required String key,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    _store.remove(key);
  }
}

late AppDatabase testDb;
late SyncDatabaseHelper syncHelper;

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    testDb = AppDatabase.inMemory();
    syncHelper = SyncDatabaseHelper(testDb);
    // Insert a test store for foreign key constraints
    await testDb
        .into(testDb.stores)
        .insert(StoresCompanion.insert(name: 'Test Store'));
  });

  tearDown(() async {
    await testDb.close();
  });

  test('batch push applies id_map to local product and marks synced', () async {
    final d = await syncHelper.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final localId = await d.insert('products', {
      'store_id': 1,
      'name': 'TmpProd',
      'sku': 'TP01',
      'price': 1.0,
      'stock_quantity': 4,
      'is_synced': 0,
      'last_updated': now
    });

    final payload = jsonEncode({
      'table': 'products',
      'row_id': localId,
      'action': 'CREATE',
      'data': {
        'name': 'TmpProd',
        'sku': 'TP01',
        'price': 1.0,
        'stock_quantity': 4,
        'store_id': 1
      }
    });

    await d.insert('sync_queue', {
      'table_name': 'products',
      'row_id': localId,
      'action': 'CREATE',
      'payload': payload,
      'created_at': now,
      'retry_count': 0,
      'status': 'pending'
    });

    final builder = FakeHttpClient();
    builder.when('/api/sync/push', (req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final changes = (body['changes'] as List).cast<Map<String, dynamic>>();
      // Expect one change with temp_id t{localId}
      final temp = changes.first['temp_id'] as String;
      return http.Response(
          jsonEncode({
            'applied': [
              {'resource_type': 'product', 'operation': 'create', 'id': 555}
            ],
            'conflicts': [],
            'id_map': {temp: 555}
          }),
          200,
          headers: {'content-type': 'application/json'});
    });

    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');

    final svc = PostgresSyncService(
        db: syncHelper,
        api: api,
        syncRepo: SyncRepository(dbHelper: syncHelper),
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);

    final ok = await svc.syncPendingChangesBatch();
    expect(ok, isTrue);

    final rows =
        await d.query('products', where: 'id = ?', whereArgs: [localId]);
    expect(rows.first['server_id'], 555);

    final qrows =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [localId]);
    expect(qrows.first['status'], 'synced');
  });

  test('batch push logs conflict and increments retry', () async {
    final d = await syncHelper.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final localId = await d.insert('products', {
      'store_id': 1,
      'name': 'ConfProd',
      'sku': 'CP01',
      'price': 1.0,
      'stock_quantity': 4,
      'is_synced': 0,
      'last_updated': now
    });

    final payload = jsonEncode({
      'table': 'products',
      'row_id': localId,
      'action': 'CREATE',
      'payload': {}
    });

    await d.insert('sync_queue', {
      'table_name': 'products',
      'row_id': localId,
      'action': 'CREATE',
      'payload': payload,
      'created_at': now,
      'retry_count': 4,
      'status': 'pending'
    });

    final builder = FakeHttpClient();
    builder.when('/api/sync/push', (req) async {
      return http.Response(
          jsonEncode({
            'applied': [],
            'conflicts': [
              {'resource_type': 'product', 'id': null, 'message': 'bad data'}
            ],
            'id_map': {}
          }),
          200,
          headers: {'content-type': 'application/json'});
    });

    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');

    final svc = PostgresSyncService(
        db: syncHelper,
        api: api,
        syncRepo: SyncRepository(dbHelper: syncHelper),
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);

    final ok = await svc.syncPendingChangesBatch();
    expect(ok, isTrue);

    final qrows =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [localId]);
    expect(qrows.first['retry_count'], 5);
    expect(qrows.first['status'], 'failed');

    final errors = await d.query('sync_errors');
    expect(errors.length, greaterThanOrEqualTo(1));
  });

  test('batch push applies multiple id_map mappings and marks all synced',
      () async {
    final d = await syncHelper.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final idA = await d.insert('products', {
      'store_id': 1,
      'name': 'TmpA',
      'sku': 'TA01',
      'price': 2.0,
      'stock_quantity': 1,
      'is_synced': 0,
      'last_updated': now
    });
    final idB = await d.insert('products', {
      'store_id': 1,
      'name': 'TmpB',
      'sku': 'TB01',
      'price': 3.0,
      'stock_quantity': 2,
      'is_synced': 0,
      'last_updated': now
    });

    final payloadA = jsonEncode(
        {'table': 'products', 'row_id': idA, 'action': 'CREATE', 'data': {}});
    final payloadB = jsonEncode(
        {'table': 'products', 'row_id': idB, 'action': 'CREATE', 'data': {}});

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
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final changes = (body['changes'] as List).cast<Map<String, dynamic>>();
      final tempA = changes[0]['temp_id'] as String;
      final tempB = changes[1]['temp_id'] as String;
      return http.Response(
          jsonEncode({
            'applied': [],
            'conflicts': [],
            'id_map': {tempA: 1001, tempB: 1002}
          }),
          200,
          headers: {'content-type': 'application/json'});
    });

    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');

    final svc = PostgresSyncService(
        db: syncHelper,
        api: api,
        syncRepo: SyncRepository(dbHelper: syncHelper),
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);

    final ok = await svc.syncPendingChangesBatch();
    expect(ok, isTrue);

    final rowA =
        (await d.query('products', where: 'id = ?', whereArgs: [idA])).first;
    final rowB =
        (await d.query('products', where: 'id = ?', whereArgs: [idB])).first;
    expect(rowA['server_id'], 1001);
    expect(rowB['server_id'], 1002);

    final qA =
        (await d.query('sync_queue', where: 'row_id = ?', whereArgs: [idA]))
            .first;
    final qB =
        (await d.query('sync_queue', where: 'row_id = ?', whereArgs: [idB]))
            .first;
    expect(qA['status'], 'synced');
    expect(qB['status'], 'synced');
  });

  test('batch push applies transaction applied data and updates local sale',
      () async {
    final d = await syncHelper.database;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Create a user for FK
    final userId = await d.insert('users', {
      'username': 'tester',
      'password_hash': 'x',
      'role': 'cashier',
      'store_id': 1,
      'is_active': 1,
      'created_at': now,
      'last_updated_at': now
    });

    // Create a local sale (pending sync)
    final saleId = await d.insert('sales', {
      'transaction_number': 'LOCAL-TXN',
      'total_amount': 6.0,
      'payment_method': 'card',
      'status': 'completed',
      'store_id': 1,
      'user_id': userId,
      'created_at': now,
      'last_updated_at': now,
      'sync_status': 'pending'
    });

    // Enqueue sync item for sale
    final payload = jsonEncode({
      'table': 'sale',
      'row_id': saleId,
      'action': 'CREATE',
      'data': {
        'transaction_number': 'LOCAL-TXN',
        'total_amount': 6.0,
        'payment_method': 'card',
        'status': 'completed',
        'store_id': 1,
        'user_id': userId,
        'items': []
      }
    });

    await d.insert('sync_queue', {
      'table_name': 'sale',
      'row_id': saleId,
      'action': 'CREATE',
      'payload': payload,
      'created_at': now,
      'retry_count': 0,
      'status': 'pending'
    });

    final builder = FakeHttpClient();
    builder.when('/api/sync/push', (req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final changes = (body['changes'] as List).cast<Map<String, dynamic>>();
      final temp = changes.first['temp_id'] as String;
      const serverId = 444;
      return http.Response(
          jsonEncode({
            'applied': [
              {
                'resource_type': 'transaction',
                'operation': 'create',
                'id': serverId,
                'data': {
                  'transaction_number': 'SERVER-444',
                  'store_id': 1,
                  'user_id': 1,
                  'total_amount': 6.0,
                  'payment_method': 'card'
                }
              }
            ],
            'conflicts': [],
            'id_map': {temp: serverId}
          }),
          200,
          headers: {'content-type': 'application/json'});
    });

    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');

    final svc = PostgresSyncService(
        db: syncHelper,
        api: api,
        syncRepo: SyncRepository(dbHelper: syncHelper),
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);

    final ok = await svc.syncPendingChangesBatch();
    expect(ok, isTrue);

    final rows = await d.query('sales', where: 'id = ?', whereArgs: [saleId]);
    expect(rows.first['server_id'], 444);
    expect(rows.first['transaction_number'], 'SERVER-444');

    final qrows =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [saleId]);
    expect(qrows.first['status'], 'synced');
  });

  test('sale with unsynced local product creates product in same batch',
      () async {
    final d = await syncHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Create an unsynced local product (no server_id)
    final localProdId = await d.insert('products', {
      'store_id': 1,
      'name': 'Sauce 500ml',
      'sku': 'S500',
      'price': 0.5,
      'stock_quantity': 28,
      'is_synced': 0,
      'last_updated': now
    });

    // Create sale referencing local product
    final userId = await d.insert('users', {
      'username': 'tester2',
      'password_hash': 'x',
      'role': 'cashier',
      'store_id': 1,
      'is_active': 1,
      'created_at': now,
      'last_updated_at': now
    });

    final saleId = await d.insert('sales', {
      'transaction_number': 'LOCAL-TXN-2',
      'total_amount': 10.0,
      'payment_method': 'cash',
      'status': 'completed',
      'store_id': 1,
      'user_id': userId,
      'created_at': now,
      'last_updated_at': now,
      'sync_status': 'pending'
    });

    // Add sale item using local product id
    await d.insert('sale_items', {
      'sale_id': saleId,
      'product_id': localProdId,
      'quantity': 2,
      'unit_price': 5.0,
      'total_price': 10.0,
      'sync_status': 'pending'
    });

    // Enqueue sync item for sale only (no separate product queue item)
    final payload = jsonEncode({
      'table': 'sale',
      'row_id': saleId,
      'action': 'CREATE',
      'data': {
        'transaction_number': 'LOCAL-TXN-2',
        'total_amount': 10.0,
        'payment_method': 'cash',
        'status': 'completed',
        'store_id': 1,
        'user_id': userId,
        'items': [
          {
            'product_id': 't$localProdId',
            'quantity': 2,
            'unit_price': 5.0,
            'total_price': 10.0
          }
        ]
      }
    });

    await d.insert('sync_queue', {
      'table_name': 'sale',
      'row_id': saleId,
      'action': 'CREATE',
      'payload': payload,
      'created_at': now,
      'retry_count': 0,
      'status': 'pending'
    });

    final builder = FakeHttpClient();
    builder.when('/api/sync/push', (req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final changes = (body['changes'] as List).cast<Map<String, dynamic>>();

      // Expect a product create for t<localProdId> and a transaction create referencing it
      final hasProductCreate =
          changes.any((c) => c['resource_type'] == 'product');
      final hasTxnCreate =
          changes.any((c) => c['resource_type'] == 'transaction');
      expect(hasProductCreate, isTrue);
      expect(hasTxnCreate, isTrue);

      final tempProd =
          changes.firstWhere((c) => c['resource_type'] == 'product')['temp_id']
              as String;
      const serverProdId = 7777;
      const serverTxnId = 8888;

      return http.Response(
          jsonEncode({
            'applied': [
              {
                'resource_type': 'product',
                'operation': 'create',
                'id': serverProdId
              },
              {
                'resource_type': 'transaction',
                'operation': 'create',
                'id': serverTxnId,
                'data': {
                  'transaction_number': 'SERVER-TXN-8888',
                  'store_id': 1,
                  'user_id': 1,
                  'total_amount': 10.0,
                  'payment_method': 'cash'
                }
              }
            ],
            'conflicts': [],
            'id_map': {tempProd: serverProdId}
          }),
          200,
          headers: {'content-type': 'application/json'});
    });

    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');

    final svc = PostgresSyncService(
        db: syncHelper,
        api: api,
        syncRepo: SyncRepository(dbHelper: syncHelper),
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);

    final ok = await svc.syncPendingChangesBatch();
    expect(ok, isTrue);

    // Verify product got server_id
    final prodRows =
        await d.query('products', where: 'id = ?', whereArgs: [localProdId]);
    expect(prodRows.first['server_id'], 7777);

    // Verify sale got server_id and transaction_number updated from server
    final saleRows =
        await d.query('sales', where: 'id = ?', whereArgs: [saleId]);
    expect(saleRows.first['server_id'], 8888);
    expect(saleRows.first['transaction_number'], 'SERVER-TXN-8888');

    // Verify queue item marked synced
    final qrows =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [saleId]);
    expect(qrows.first['status'], 'synced');
  });

  // (Remove this duplicate code block, as it is now inside the test function above)

  test('batch push mixed operations apply update and delete properly',
      () async {
    final d = await syncHelper.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    // Existing product with server_id to update
    final updId = await d.insert('products', {
      'store_id': 1,
      'server_id': 200,
      'name': 'ToUpdate',
      'sku': 'UP01',
      'price': 5.0,
      'stock_quantity': 10,
      'is_synced': 0,
      'last_updated': now
    });
    // Existing product with server_id to delete
    final delId = await d.insert('products', {
      'store_id': 1,
      'server_id': 201,
      'name': 'ToDelete',
      'sku': 'DL01',
      'price': 1.0,
      'stock_quantity': 0,
      'is_synced': 0,
      'last_updated': now
    });

    final updPayload = jsonEncode({
      'table': 'products',
      'row_id': updId,
      'action': 'UPDATE',
      'payload': {}
    });
    final delPayload = jsonEncode({
      'table': 'products',
      'row_id': delId,
      'action': 'DELETE',
      'payload': {}
    });

    await d.insert('sync_queue', {
      'table_name': 'products',
      'row_id': updId,
      'action': 'UPDATE',
      'payload': updPayload,
      'created_at': now,
      'retry_count': 0,
      'status': 'pending'
    });

    await d.insert('sync_queue', {
      'table_name': 'products',
      'row_id': delId,
      'action': 'DELETE',
      'payload': delPayload,
      'created_at': now,
      'retry_count': 0,
      'status': 'pending'
    });

    final builder = FakeHttpClient();
    builder.when('/api/sync/push', (req) async {
      return http.Response(
          jsonEncode({
            'applied': [
              {'resource_type': 'product', 'operation': 'update', 'id': 200},
              {'resource_type': 'product', 'operation': 'delete', 'id': 201}
            ],
            'conflicts': [],
            'id_map': {}
          }),
          200,
          headers: {'content-type': 'application/json'});
    });

    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');

    final svc = PostgresSyncService(
        db: syncHelper,
        api: api,
        syncRepo: SyncRepository(dbHelper: syncHelper),
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);

    final ok = await svc.syncPendingChangesBatch();
    expect(ok, isTrue);

    final updated =
        (await d.query('products', where: 'server_id = ?', whereArgs: [200]));
    expect(updated.first['is_synced'], 1);

    final deleted =
        await d.query('products', where: 'server_id = ?', whereArgs: [201]);
    expect(deleted, isEmpty);

    final qUpd =
        (await d.query('sync_queue', where: 'row_id = ?', whereArgs: [updId]))
            .first;
    final qDel =
        (await d.query('sync_queue', where: 'row_id = ?', whereArgs: [delId]))
            .first;
    expect(qUpd['status'], 'synced');
    expect(qDel['status'], 'synced');
  });

  test('batch push applies server-provided data for created product', () async {
    final d = await syncHelper.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final localId = await d.insert('products', {
      'store_id': 1,
      'name': 'TmpProd2',
      'sku': 'TP02',
      'price': 1.0,
      'stock_quantity': 4,
      'is_synced': 0,
      'last_updated': now
    });

    final payload = jsonEncode({
      'table': 'products',
      'row_id': localId,
      'action': 'CREATE',
      'data': {}
    });

    await d.insert('sync_queue', {
      'table_name': 'products',
      'row_id': localId,
      'action': 'CREATE',
      'payload': payload,
      'created_at': now,
      'retry_count': 0,
      'status': 'pending'
    });

    final builder = FakeHttpClient();
    builder.when('/api/sync/push', (req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final changes = (body['changes'] as List).cast<Map<String, dynamic>>();
      final temp = changes.first['temp_id'] as String;
      return http.Response(
          jsonEncode({
            'applied': [
              {
                'resource_type': 'product',
                'operation': 'create',
                'id': 777,
                'data': {
                  'name': 'SrvName',
                  'sku': 'S01',
                  'price': 9.99,
                  'stock_quantity': 99
                }
              }
            ],
            'conflicts': [],
            'id_map': {temp: 777}
          }),
          200,
          headers: {'content-type': 'application/json'});
    });

    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');

    final svc = PostgresSyncService(
        db: syncHelper,
        api: api,
        syncRepo: SyncRepository(dbHelper: syncHelper),
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);

    final ok = await svc.syncPendingChangesBatch();
    expect(ok, isTrue);

    final rows =
        await d.query('products', where: 'id = ?', whereArgs: [localId]);
    final r = rows.first;
    expect(r['server_id'], 777);
    expect(r['name'], 'SrvName');
    expect(r['price'], 9.99);
    expect(r['stock_quantity'], 99);

    final qrows =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [localId]);
    expect(qrows.first['status'], 'synced');
  });

  test('batch push applies server-provided data for update', () async {
    final d = await syncHelper.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final updId = await d.insert('products', {
      'store_id': 1,
      'server_id': 300,
      'name': 'LocalName',
      'sku': 'LN01',
      'price': 5.0,
      'stock_quantity': 10,
      'is_synced': 0,
      'last_updated': now
    });

    final updPayload = jsonEncode({
      'table': 'products',
      'row_id': updId,
      'action': 'UPDATE',
      'payload': {}
    });

    await d.insert('sync_queue', {
      'table_name': 'products',
      'row_id': updId,
      'action': 'UPDATE',
      'payload': updPayload,
      'created_at': now,
      'retry_count': 0,
      'status': 'pending'
    });

    final builder = FakeHttpClient();
    builder.when('/api/sync/push', (req) async {
      return http.Response(
          jsonEncode({
            'applied': [
              {
                'resource_type': 'product',
                'operation': 'update',
                'id': 300,
                'data': {
                  'name': 'RemoteName',
                  'price': 7.5,
                  'stock_quantity': 55
                }
              }
            ],
            'conflicts': [],
            'id_map': {}
          }),
          200,
          headers: {'content-type': 'application/json'});
    });

    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');

    final svc = PostgresSyncService(
        db: syncHelper,
        api: api,
        syncRepo: SyncRepository(dbHelper: syncHelper),
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);

    final ok = await svc.syncPendingChangesBatch();
    expect(ok, isTrue);

    final updated =
        (await d.query('products', where: 'server_id = ?', whereArgs: [300]))
            .first;
    expect(updated['name'], 'RemoteName');
    expect(updated['price'], 7.5);
    expect(updated['stock_quantity'], 55);
    expect(updated['is_synced'], 1);

    final qUpd =
        (await d.query('sync_queue', where: 'row_id = ?', whereArgs: [updId]))
            .first;
    expect(qUpd['status'], 'synced');
  });
}
