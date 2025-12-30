import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/remote/postgres_api_service.dart';
import 'package:mobile/data/sync/postgres_sync_service.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'package:sqflite/sqflite.dart' as sqflite_common;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import '../test_helpers.dart';

class FakeApi extends PostgresApiService {
  final Map<String, dynamic> payload;
  FakeApi(this.payload) : super(baseUrl: 'http://localhost');

  @override
  Future<Map<String, dynamic>> fetchChangesSinceSeq(int sinceSeq,
      {String? token, int limit = 500, String? types}) async {
    return payload;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PostgresSyncService.pullChangesSinceSeq', () {
    setUp(() async {
      // Initialize shared test helpers (sqflite ffi, platform bindings, etc.)
      initSqfliteForTests();

      await DatabaseHelper.initTestDb();
    });

    tearDown(() async {
      await DatabaseHelper.resetTestDb();
    });

    test('applies product create/update/delete and updates last_server_seq',
        () async {
      final db = DatabaseHelper();
      final api = FakeApi({
        'changes': [
          {
            'entity_type': 'product',
            'entity_id': '1001',
            'operation': 'create',
            'payload': {
              'data': {
                'name': 'NEW',
                'sku': 'sku-1001',
                'price': 5.0,
                'stock_quantity': 10,
                'store_id': 1
              }
            },
            'server_seq': 10
          },
          {
            'entity_type': 'product',
            'entity_id': '1001',
            'operation': 'update',
            'payload': {
              'data': {'name': 'NEW-UPDATED', 'price': 6.0}
            },
            'server_seq': 11
          },
          {
            'entity_type': 'product',
            'entity_id': '1001',
            'operation': 'delete',
            'payload': {},
            'server_seq': 12
          }
        ],
        'head_seq': 12
      });

      // Use top-level FakeStorage to provide token for the pull call
      final svc = PostgresSyncService(
          db: db, api: api, secureStorage: FakeFlutterSecureStorage());

      await svc.pullChangesSinceSeq();

      final dbClient = await db.database;
      final rows = await dbClient
          .query('products', where: 'server_id = ?', whereArgs: [1001]);
      expect(rows, isEmpty);

      final seq = await db.getLastServerSeq();
      expect(seq, 12);
    });
  });
}
