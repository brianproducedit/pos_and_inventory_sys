import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/sync/sync_service.dart';
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pushChanges applies id_map and clears queue', () async {
    final fakeDb = _FakeDb();

    // create a queue item: temp_id tmp-1
    final payload = jsonEncode({
      'resource_type': 'product',
      'operation': 'create',
      'temp_id': 'tmp-1',
      'data': {'name': 'Widget', 'price': 1.23, 'stock_quantity': 5}
    });
    fakeDb.queue.add(_FakeQueueItem(11, payload));

    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/api/sync/push')) {
        return http.Response(
            jsonEncode({
              'applied': [
                {'operation': 'create', 'id': 101}
              ],
              'id_map': {'tmp-1': 101},
              'conflicts': []
            }),
            200);
      }
      return http.Response('{}', 200);
    });

    final svc = SyncService(fakeDb as dynamic, httpClient: mockClient);

    final res = await svc.pushChanges();
    expect(res['id_map'], isNotEmpty);
    expect(fakeDb.updatedServerIds.length, 1);
    expect(fakeDb.deletedQueueIds, contains(11));
  });

  test('pullChanges inserts server products', () async {
    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/api/sync/changes')) {
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
            200);
      }
      return http.Response('{}', 200);
    });

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
