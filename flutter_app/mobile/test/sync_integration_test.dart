import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/sync/sync_service.dart';
import 'test_utils/fake_http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeQueueItem {
  final int id;
  final String payloadJson;
  _FakeQueueItem(this.id, this.payloadJson);
}

class _FakeDb {
  List<_FakeQueueItem> queue = [];
  List<Map<String, dynamic>> insertedProducts = [];
  List<int> deletedQueueIds = [];
  List<Map<String, dynamic>> updatedServerIds = [];

  Future<List<_FakeQueueItem>> getPendingChanges() async => queue;
  Future<int> deleteQueueItem(int id) async {
    deletedQueueIds.add(id);
    queue.removeWhere((q) => q.id == id);
    return 1;
  }

  Future<int> updateQueuePayload(int id, String payloadJson) async {
    final idx = queue.indexWhere((q) => q.id == id);
    if (idx == -1) return 0;
    queue[idx] = _FakeQueueItem(queue[idx].id, payloadJson);
    return 1;
  }

  Future<int> updateProductServerId(String clientId, int serverId) async {
    updatedServerIds.add({'clientId': clientId, 'serverId': serverId});
    return 1;
  }

  Future<int> insertProduct(dynamic data) async {
    // Accept either Map or a ProductsCompanion
    if (data is Map<String, dynamic>) {
      insertedProducts.add(data);
    } else {
      // Try to extract the name/price/stock fields if it's a companion
      try {
        final name = (data as dynamic).name?.value as String? ?? '';
        final price = (data as dynamic).price?.value as double? ?? 0.0;
        final stock = (data as dynamic).stockQuantity?.value as int? ?? 0;
        insertedProducts
            .add({'name': name, 'price': price, 'stock_quantity': stock});
      } catch (_) {
        insertedProducts.add({'raw': data.toString()});
      }
    }
    return 1;
  }

  Future<int> updateQueuePayloadNotUsedByOtherTestsOnlyForDocs() async => 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('attachStoreToPendingCreates updates pending product creates', () async {
    final fakeDb = _FakeDb();

    final payload1 = jsonEncode({
      'resource_type': 'product',
      'operation': 'create',
      'temp_id': 'tmp-a',
      'data': {'name': 'Local', 'price': 2.0}
    });
    final payload2 = jsonEncode({
      'resource_type': 'product',
      'operation': 'update',
      'id': 201,
      'data': {'name': 'ServerEdit'}
    });
    fakeDb.queue.add(_FakeQueueItem(1, payload1));
    fakeDb.queue.add(_FakeQueueItem(2, payload2));
    final svc = SyncService(fakeDb as dynamic);
    final updated = await svc.attachStoreToPendingCreates(storeId: 5);
    expect(updated, 1);
    final updatedPayload =
        fakeDb.queue.firstWhere((q) => q.id == 1).payloadJson;
    final p = jsonDecode(updatedPayload) as Map<String, dynamic>;
    expect(p['data']['store_id'], 5);
  });

  test('pushChanges applies id_map and clears queue', () async {
    final fakeDb = _FakeDb();

    // create a queue item: temp_id tmp-1
    final payload = jsonEncode({
      'resource_type': 'product',
      'operation': 'create',
      'temp_id': 'tmp-1',
      'data': {
        'name': 'Widget',
        'price': 1.23,
        'stock_quantity': 5,
        'store_id': 1
      }
    });
    fakeDb.queue.add(_FakeQueueItem(11, payload));

    final builder = FakeHttpClient();
    builder.when('/api/sync/push', (request) async {
      return http.Response(
          jsonEncode({
            'applied': [
              {'operation': 'create', 'id': 101}
            ],
            'id_map': {'tmp-1': 101},
            'conflicts': []
          }),
          200,
          headers: {'content-type': 'application/json'});
    });
    final mockClient = builder.build();

    final svc = SyncService(fakeDb as dynamic, httpClient: mockClient);

    final res = await svc.pushChanges();
    expect(res['id_map'], isNotEmpty);
    expect(fakeDb.updatedServerIds.length, 1);
    expect(fakeDb.deletedQueueIds, contains(11));
  });

  test('pullChanges inserts server products', () async {
    final builder = FakeHttpClient();
    builder.when('/api/sync/changes', (request) async {
      return http.Response(
          jsonEncode({
            'changes': {
              'products': [
                {
                  'data': {
                    'name': 'Server Product',
                    'price': 9.99,
                    'stock_quantity': 10,
                    'store_id': 1
                  }
                }
              ]
            }
          }),
          200,
          headers: {'content-type': 'application/json'});
    });
    final mockClient = builder.build();

    final fakeDb = _FakeDb();
    SharedPreferences.setMockInitialValues({});
    final svc = SyncService(fakeDb as dynamic, httpClient: mockClient);

    final prods =
        await svc.pullChanges(since: DateTime.fromMillisecondsSinceEpoch(0));
    expect(prods, isNotEmpty);
    expect(fakeDb.insertedProducts.length, 1);
    expect(fakeDb.insertedProducts.first['name'], 'Server Product');
  });
}
