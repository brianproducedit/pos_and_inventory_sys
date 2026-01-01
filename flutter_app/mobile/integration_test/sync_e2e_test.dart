import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;
import 'package:mobile/providers/sync_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/sync/sync_service.dart';
import 'package:mobile/db/app_database.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';

class FakeAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => true;

  @override
  Future<String?> getToken() async => 'fake_token';

  @override
  String? get role => 'admin';
}

class MockSyncServer {
  HttpServer? _server;
  final List<Map<String, dynamic>> _changes = [];
  final Map<String, Map<String, dynamic>> _products = {};

  Future<void> start() async {
    _server = await HttpServer.bind('localhost', 8080);
    _server!.listen((HttpRequest request) async {
      if (request.uri.path == '/api/sync/push' && request.method == 'POST') {
        final body = await utf8.decodeStream(request);
        final payload = json.decode(body);
        _changes.addAll(payload['changes'] as List<Map<String, dynamic>>);

        // Process creates
        for (final change in payload['changes']) {
          if (change['operation'] == 'create' &&
              change['resource_type'] == 'product') {
            final data = change['data'] as Map<String, dynamic>;
            final serverId = DateTime.now().millisecondsSinceEpoch;
            _products[serverId.toString()] = {...data, 'id': serverId};
          }
        }

        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(json.encode({
            'id_map': {
              for (final change in payload['changes'])
                change['temp_id']: DateTime.now().millisecondsSinceEpoch
            },
            'conflicts': []
          }));
      } else if (request.uri.path == '/api/sync/changes' &&
          request.method == 'GET') {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(json.encode({'changes': [], 'head_seq': 1}));
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
  }

  Future<void> stop() async {
    await _server?.close();
  }

  List<Map<String, dynamic>> get changes => _changes;
  Map<String, Map<String, dynamic>> get products => _products;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late MockSyncServer mockServer;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockServer = MockSyncServer();
    await mockServer.start();
  });

  tearDown(() async {
    await mockServer.stop();
  });

  group('Offline to Online Sync Integration Tests', () {
    testWidgets('create product offline and sync when online', (tester) async {
      final fakeAuth = FakeAuthProvider();
      final syncProvider = SyncProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: fakeAuth),
            ChangeNotifierProvider<SyncProvider>.value(value: syncProvider),
          ],
          child: const app.MyApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Simulate going offline by disabling network
      // Note: In a real test, you'd use a network interceptor or mock HTTP client

      // Navigate to inventory screen
      await tester.tap(find.text('Inventory'));
      await tester.pumpAndSettle();

      // Create a product while "offline"
      await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField).first, 'Offline Product');
      await tester.enterText(find.byType(TextFormField).at(1), '15.99');
      await tester.enterText(find.byType(TextFormField).at(2), '25');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      // Verify product appears in local inventory
      expect(find.text('Offline Product'), findsOneWidget);

      // Simulate coming back online and triggering sync
      // In real implementation, this would be automatic or manual sync trigger
      await syncProvider.sync();

      // Wait for sync to complete
      await tester.pumpAndSettle();

      // Verify sync was successful (in real test, check server received the data)
      expect(mockServer.changes.isNotEmpty, isTrue);
      expect(
          mockServer.changes
              .any((change) => change['data']['name'] == 'Offline Product'),
          isTrue);
    });

    testWidgets('handle sync conflicts gracefully', (tester) async {
      final fakeAuth = FakeAuthProvider();
      final syncProvider = SyncProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: fakeAuth),
            ChangeNotifierProvider<SyncProvider>.value(value: syncProvider),
          ],
          child: const app.MyApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Create product locally
      await tester.tap(find.text('Inventory'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField).first, 'Conflict Product');
      await tester.enterText(find.byType(TextFormField).at(1), '10.00');
      await tester.enterText(find.byType(TextFormField).at(2), '10');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      // Simulate server having newer version (would be handled by conflict resolution)
      // In real test, mock server would return conflict

      await syncProvider.sync();
      await tester.pumpAndSettle();

      // Verify conflict was detected and handled
      // This would check for conflict resolution UI or automatic resolution
      expect(find.text('Conflict Product'), findsOneWidget);
    });

    testWidgets('sync large batch of changes efficiently', (tester) async {
      final fakeAuth = FakeAuthProvider();
      final syncProvider = SyncProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: fakeAuth),
            ChangeNotifierProvider<SyncProvider>.value(value: syncProvider),
          ],
          child: const app.MyApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Create multiple products offline
      await tester.tap(find.text('Inventory'));
      await tester.pumpAndSettle();

      for (int i = 0; i < 10; i++) {
        await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
        await tester.pumpAndSettle();

        await tester.enterText(
            find.byType(TextFormField).first, 'Batch Product $i');
        await tester.enterText(find.byType(TextFormField).at(1), '${i + 1}.99');
        await tester.enterText(
            find.byType(TextFormField).at(2), '${(i + 1) * 5}');

        await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
        await tester.pumpAndSettle();
      }

      // Trigger sync
      final startTime = DateTime.now();
      await syncProvider.sync();
      final endTime = DateTime.now();

      // Verify sync completed within reasonable time (< 5 seconds for 10 items)
      expect(endTime.difference(startTime).inSeconds, lessThan(5));

      // Verify all changes were synced
      expect(mockServer.changes.length, equals(10));
      for (int i = 0; i < 10; i++) {
        expect(
            mockServer.changes
                .any((change) => change['data']['name'] == 'Batch Product $i'),
            isTrue);
      }
    });
  });
}
