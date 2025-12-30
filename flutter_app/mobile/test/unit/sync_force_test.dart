import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/sync/sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../test_utils/fake_http_client.dart';

void main() {
  test('forceUpdate sends _force and returns applied', () async {
    // Use shared FakeHttpClient helper so route handling is consistent across tests
    final builder = FakeHttpClient();
    builder.when('/api/sync/push', (request) async {
      // Check body contains _force
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final changes = (body['changes'] as List).cast<Map<String, dynamic>>();
      expect(changes.length, 1);
      final data = changes.first['data'] as Map<String, dynamic>;
      expect(data.containsKey('_force'), true);

      final resp = jsonEncode({
        'applied': [
          {'resource_type': 'product', 'operation': 'update', 'id': 42}
        ],
        'conflicts': [],
        'id_map': {}
      });
      return http.Response(resp, 200,
          headers: {'content-type': 'application/json'});
    });
    final mockClient = builder.build();

    // Use a fake db object because forceUpdate doesn't use the DB
    final svc = SyncService(null,
        httpClient: mockClient, serverBase: 'http://localhost:8000');

    final res = await svc
        .forceUpdate(resourceType: 'product', id: 42, data: {'price': 10.0});
    expect(res['applied'], isNotEmpty);
    expect((res['applied'] as List).first['id'], 42);
  });
}
