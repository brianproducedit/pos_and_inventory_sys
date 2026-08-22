import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/data/sync/sync_database_helper.dart';
import 'package:mobile/db/app_database.dart';
import 'package:mobile/data/remote/postgres_api_service.dart';
import 'package:mobile/data/sync/postgres_sync_service.dart';
import 'package:mobile/data/repositories/sync_repository.dart';
import 'package:mobile/sync/sync_background.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'run_background_integration_test_helper.dart';

class _FakeConnectivity implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class TestSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    required String key,
    required String? value,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
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
    AppleOptions? iOptions,
    required String key,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async =>
      _store[key];

  @override
  Future<void> delete({
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    required String key,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    _store.remove(key);
  }
}

late AppDatabase testDb;
late SyncDatabaseHelper syncHelper;

void main() {
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

  test('runBackgroundTask records sync_error on 409 conflict', () async {
    final db = SyncDatabaseHelper(testDb);
    final d = await db.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final localId = await d.insert('products', {
      'store_id': 1,
      'server_id': 200,
      'name': 'ConflictProd',
      'sku': 'C01',
      'price': 5.0,
      'stock_quantity': 2,
      'is_synced': 0,
      'last_updated': now
    });

    // enqueue an update
    final payload = jsonEncode({
      'table': 'products',
      'row_id': localId,
      'action': 'UPDATE',
      'payload': {}
    });

    final qid = await d.insert('sync_queue', {
      'table_name': 'products',
      'row_id': localId,
      'action': 'UPDATE',
      'payload': payload,
      'created_at': now,
      'retry_count': 0,
      'status': 'pending'
    });

    // Fake HTTP client that returns conflict for the batch push
    final fake = _FakeHttpClient((req) async {
      if (req.method == 'POST' && req.url.path == '/api/sync/push') {
        // Return a conflict in the batch push response
        return http.Response(
            jsonEncode({
              'applied': [],
              'conflicts': [
                {
                  'resource_type': 'product',
                  'id': 200,
                  'message': 'conflict',
                  'server_data': {'name': 'Server Version'}
                }
              ],
              'id_map': {}
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 200);
    });

    final api = PostgresApiService(client: fake);

    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'access_token', value: 'tok-123');

    final svc = PostgresSyncService(
        db: db,
        api: api,
        syncRepo: SyncRepository(dbHelper: db),
        httpClient: fake,
        connectivity: _FakeConnectivity(),
        secureStorage: fakeStore);

    final result = await runBackgroundTask(
        openDb: () async => NoopDb(), syncServiceFactory: (db) => svc);

    expect(result, isTrue);

    final qrows =
        await d.query('sync_queue', where: 'id = ?', whereArgs: [qid]);
    expect(qrows.first['retry_count'], greaterThanOrEqualTo(1));

    final errors =
        await d.query('sync_errors', where: 'queue_id = ?', whereArgs: [qid]);
    expect(errors, isNotEmpty);
  });
}

// Minimal fake HTTP client wrapper used only in this test
class _FakeHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request req) _handler;
  _FakeHttpClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = http.Request(request.method, request.url);
    req.headers.addAll(request.headers);
    if (request is http.Request && request.body.isNotEmpty) {
      req.body = request.body;
    }
    final res = await _handler(req);
    final bytes = utf8.encode(res.body);
    return http.StreamedResponse(Stream.fromIterable([bytes]), res.statusCode,
        headers: res.headers);
  }

  @override
  void close() {}
}
