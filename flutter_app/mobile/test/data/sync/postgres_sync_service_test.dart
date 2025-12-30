import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile/data/sync/postgres_sync_service.dart';
import 'package:mobile/data/remote/postgres_api_service.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../test_utils/fake_http_client.dart';
import '../../test_helpers.dart';

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
    if (value == null)
      _store.remove(key);
    else
      _store[key] = value;
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
  }) async =>
      _store.remove(key);
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

  test('syncPendingChanges handles successful product CREATE', () async {
    final db = DatabaseHelper();
    final d = await db.database;

    // Insert a local product (unsynced)
    final now = DateTime.now().millisecondsSinceEpoch;
    final localId = await d.insert('products', {
      'store_id': 1,
      'name': 'LocalProd',
      'sku': 'LP01',
      'price': 2.0,
      'stock_quantity': 3,
      'is_synced': 0,
      'last_updated': now
    });

    final payload = jsonEncode({
      'table': 'products',
      'row_id': localId,
      'action': 'CREATE',
      'data': {
        'name': 'LocalProd',
        'sku': 'LP01',
        'price': 2.0,
        'stock_quantity': 3,
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
    builder.when('/api/products', (req) async {
      return http.Response(jsonEncode({'id': 101, 'name': 'LocalProd'}), 201,
          headers: {'content-type': 'application/json'});
    });
    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');
    final svc = PostgresSyncService(
        db: db,
        api: api,
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);

    final ok = await svc.syncPendingChanges();
    expect(ok, isTrue);

    // Product should have server_id and queue item marked synced
    final rows =
        await d.query('products', where: 'id = ?', whereArgs: [localId]);
    expect(rows.first['server_id'], 101);

    final qrows =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [localId]);
    expect(qrows.first['status'], 'synced');
  });

  test('syncPendingChanges logs conflict on 409 and increments retry',
      () async {
    final db = DatabaseHelper();
    final d = await db.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final localId = await d.insert('products', {
      'store_id': 1,
      'name': 'LocalProd',
      'sku': 'LP02',
      'price': 2.0,
      'stock_quantity': 3,
      'is_synced': 0,
      'last_updated': now
    });

    final payload = jsonEncode({
      'table': 'products',
      'row_id': localId,
      'action': 'CREATE',
      'data': {
        'name': 'LocalProd',
        'sku': 'LP02',
        'price': 2.0,
        'stock_quantity': 3,
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
    builder.when('/api/products', (req) async {
      return http.Response(
          jsonEncode({
            'conflicts': ['conflict']
          }),
          409,
          headers: {'content-type': 'application/json'});
    });
    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');
    final svc = PostgresSyncService(
        db: db,
        api: api,
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);
    final ok = await svc.syncPendingChanges();
    expect(ok, isTrue);

    final qrows =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [localId]);
    expect(qrows.first['retry_count'], 1);

    final errors = await d.query('sync_errors');
    expect(errors.length, greaterThanOrEqualTo(1));
  });

  test('syncPendingChanges increments retry on server error', () async {
    final db = DatabaseHelper();
    final d = await db.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final localId = await d.insert('products', {
      'store_id': 1,
      'name': 'LocalProd',
      'sku': 'LP03',
      'price': 2.0,
      'stock_quantity': 3,
      'is_synced': 0,
      'last_updated': now
    });

    final payload = jsonEncode({
      'table': 'products',
      'row_id': localId,
      'action': 'CREATE',
      'data': {
        'name': 'LocalProd',
        'sku': 'LP03',
        'price': 2.0,
        'stock_quantity': 3,
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
    builder.when('/api/products', (req) async {
      return http.Response('Server error', 500);
    });
    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');
    final svc = PostgresSyncService(
        db: db,
        api: api,
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);
    final ok = await svc.syncPendingChanges();
    expect(ok, isTrue);

    final qrows =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [localId]);
    expect(qrows.first['retry_count'], 1);
  });

  test(
      'syncPendingChanges marks item failed after reaching max retries (server error)',
      () async {
    final db = DatabaseHelper();
    final d = await db.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final localId = await d.insert('products', {
      'store_id': 1,
      'name': 'LocalProd',
      'sku': 'LP04',
      'price': 2.0,
      'stock_quantity': 3,
      'is_synced': 0,
      'last_updated': now
    });

    final payload = jsonEncode({
      'table': 'products',
      'row_id': localId,
      'action': 'CREATE',
      'data': {
        'name': 'LocalProd',
        'sku': 'LP04',
        'price': 2.0,
        'stock_quantity': 3,
        'store_id': 1
      }
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
    builder.when('/api/products', (req) async {
      return http.Response('Server error', 500);
    });
    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');
    final svc = PostgresSyncService(
        db: db,
        api: api,
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);
    final ok = await svc.syncPendingChanges();
    expect(ok, isTrue);

    final qrows =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [localId]);
    expect(qrows.first['retry_count'], 5);
    expect(qrows.first['status'], 'failed');
  });

  test(
      'syncPendingChanges marks item failed after reaching max retries (conflict 409)',
      () async {
    final db = DatabaseHelper();
    final d = await db.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final localId = await d.insert('products', {
      'store_id': 1,
      'name': 'LocalProd',
      'sku': 'LP05',
      'price': 2.0,
      'stock_quantity': 3,
      'is_synced': 0,
      'last_updated': now
    });

    final payload = jsonEncode({
      'table': 'products',
      'row_id': localId,
      'action': 'CREATE',
      'data': {
        'name': 'LocalProd',
        'sku': 'LP05',
        'price': 2.0,
        'stock_quantity': 3,
        'store_id': 1
      }
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
    builder.when('/api/products', (req) async {
      return http.Response(
          jsonEncode({
            'conflicts': ['conflict']
          }),
          409,
          headers: {'content-type': 'application/json'});
    });
    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');
    final svc = PostgresSyncService(
        db: db,
        api: api,
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);
    final ok = await svc.syncPendingChanges();
    expect(ok, isTrue);

    final qrows =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [localId]);
    expect(qrows.first['retry_count'], 5);
    expect(qrows.first['status'], 'failed');

    final errors = await d.query('sync_errors');
    expect(errors.length, greaterThanOrEqualTo(1));
  });

  test('syncPendingChanges UPDATE fallback: create when server_id missing',
      () async {
    final db = DatabaseHelper();
    final d = await db.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final localId = await d.insert('products', {
      'store_id': 1,
      'name': 'LocalProd',
      'sku': 'LP06',
      'price': 5.0,
      'stock_quantity': 7,
      'is_synced': 0,
      'last_updated': now
    });

    final payload = jsonEncode({
      'table': 'products',
      'row_id': localId,
      'action': 'UPDATE',
      'data': {
        'name': 'LocalProd',
        'sku': 'LP06',
        'price': 5.0,
        'stock_quantity': 7,
        'store_id': 1
      }
    });

    await d.insert('sync_queue', {
      'table_name': 'products',
      'row_id': localId,
      'action': 'UPDATE',
      'payload': payload,
      'created_at': now,
      'retry_count': 0,
      'status': 'pending'
    });

    final builder = FakeHttpClient();
    builder.when('/api/products', (req) async {
      return http.Response(jsonEncode({'id': 202, 'name': 'LocalProd'}), 201,
          headers: {'content-type': 'application/json'});
    });
    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');
    final svc = PostgresSyncService(
        db: db,
        api: api,
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);

    final ok = await svc.syncPendingChanges();
    expect(ok, isTrue);

    final rows =
        await d.query('products', where: 'id = ?', whereArgs: [localId]);
    expect(rows.first['server_id'], 202);
    expect(rows.first['is_synced'], 1);

    final qrows =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [localId]);
    expect(qrows.first['status'], 'synced');
  });

  test(
      'syncPendingChanges DELETE without server_id deletes local product and marks synced',
      () async {
    final db = DatabaseHelper();
    final d = await db.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final localId = await d.insert('products', {
      'store_id': 1,
      'name': 'LocalProd',
      'sku': 'LP07',
      'price': 3.0,
      'stock_quantity': 2,
      'is_synced': 0,
      'last_updated': now
    });

    final payload = jsonEncode({
      'table': 'products',
      'row_id': localId,
      'action': 'DELETE',
      'data': {}
    });

    await d.insert('sync_queue', {
      'table_name': 'products',
      'row_id': localId,
      'action': 'DELETE',
      'payload': payload,
      'created_at': now,
      'retry_count': 0,
      'status': 'pending'
    });

    final builder = FakeHttpClient();
    // No network call expected, but return OK to be safe
    builder.when('/api/products', (req) async {
      return http.Response('Not used', 200);
    });
    final client = builder.build();
    final api = PostgresApiService(client: client);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');
    final svc = PostgresSyncService(
        db: db,
        api: api,
        httpClient: client,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);

    final ok = await svc.syncPendingChanges();
    expect(ok, isTrue);

    final rows =
        await d.query('products', where: 'id = ?', whereArgs: [localId]);
    expect(rows.length, 0);

    final qrows =
        await d.query('sync_queue', where: 'row_id = ?', whereArgs: [localId]);
    expect(qrows.first['status'], 'synced');
  });
}
