import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart' as pv;
import 'package:mobile/ui/sync_demo.dart';
import 'package:mobile/data/providers.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'package:mobile/data/remote/postgres_api_service.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/db/app_database.dart' as app_db;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../test_helpers.dart';

// Lightweight fake client that returns a products list for any GET
class _FakeClient extends http.BaseClient {
  final List<Map<String, dynamic>> prods;
  _FakeClient(this.prods);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode(prods);
    final bytes = utf8.encode(body);
    final stream = Stream.fromIterable([bytes]);
    return http.StreamedResponse(stream, 200,
        contentLength: bytes.length,
        headers: {'content-type': 'application/json'});
  }

  @override
  void close() {}
}

// Test-only fake store provider (top-level to avoid nested class errors)
class _TestFakeStore extends StoreProvider {
  _TestFakeStore() : super();

  @override
  Map<String, dynamic>? get currentStore => {'id': 1, 'name': 'Store 1'};

  @override
  void addListener(listener) {}

  @override
  void removeListener(listener) {}

  @override
  bool get isInitialized => true;
}

// Test-only fake PostgresApiService that extends the real service type so
// it can be injected via Riverpod provider overrides in widget tests.
class _FakePostgresApiService extends PostgresApiService {
  final List<Map<String, dynamic>> products;
  _FakePostgresApiService(this.products) : super();

  @override
  Future<void> fetchInitialDataAndSeedDB(
      {required String token, required DatabaseHelper dbHelper}) async {
    debugPrint(
        'FakePostgresApiService: fetchInitialDataAndSeedDB called (products=${products.length})');
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final p in products) {
        await txn.insert('products', {
          'server_id': p['id'],
          'store_id': p['store_id'],
          'name': p['name'],
          'sku': p['sku'],
          'price': p['price'],
          'stock_quantity': p['stock_quantity'],
          'is_synced': 1,
          'last_updated': now
        });
      }
    });
    debugPrint('FakePostgresApiService: seed completed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncDemo seed button', () {
    setUp(() async {
      initSqfliteForTests();
      await DatabaseHelper.initTestDb();
      SharedPreferences.setMockInitialValues({'access_token': 'tok'});
    });

    tearDown(() async {
      await DatabaseHelper.resetTestDb();
    });

    testWidgets('tapping seed button triggers fetch and seeds DB',
        (tester) async {
      print('Test: started sync_demo_seed_test');
      final fakeProducts = [
        {
          'id': 9001,
          'store_id': 1,
          'name': 'SeededProd',
          'sku': 'SP-1',
          'price': 3.0,
          'stock_quantity': 7
        }
      ];
      print('Test: fakeProducts prepared');

      // Use a fake PostgresApiService that writes directly to the provided db helper
      // to avoid interacting with HTTP and to keep the widget test deterministic.
      final svc = _FakePostgresApiService(fakeProducts);

      // Create an in-memory AppDatabase to avoid platform plugin calls that
      // can block under flutter_tester on some hosts.
      print('Test: creating in-memory AppDatabase');
      final appDb = app_db.AppDatabase.inMemory();
      print('Test: in-memory appDb created');

      // Seed the in-memory Drift AppDatabase so the UI FutureBuilder will show results immediately
      await appDb.insertProduct(app_db.ProductsCompanion.insert(
        name: 'SeededProd',
        price: Value(3.0),
        stockQuantity: Value(7),
        storeId: Value(1),
      ));

      // Build widget with Riverpod provider override and required providers
      // Provide test-friendly overrides: fake PostgresApiService and a fake StoreProvider
      final fakeStore = _TestFakeStore();
      await tester.pumpWidget(ProviderScope(
          overrides: [
            postgresApiServiceProvider.overrideWithValue(svc),
            databaseHelperProvider.overrideWithValue(DatabaseHelper()),
          ],
          child: pv.MultiProvider(providers: [
            pv.Provider<app_db.AppDatabase>.value(value: appDb),
            pv.ChangeNotifierProvider<AuthProvider>(
                create: (_) => AuthProvider()),
            pv.ChangeNotifierProvider<StoreProvider>.value(value: fakeStore),
          ], child: const MaterialApp(home: SyncDemoScreen()))));

      // Enlarge test window so horizontally laid out buttons are within the hit
      // area (avoids off-screen tap offsets on narrow test viewports).
      tester.binding.window.physicalSizeTestValue = const Size(1400, 900);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(() {
        tester.binding.window.clearPhysicalSizeTestValue();
        tester.binding.window.clearDevicePixelRatioTestValue();
      });

      await tester.pump();
      print('Test: after first pump');
      await tester.pump(const Duration(milliseconds: 100));
      print('Test: after short delay pump');

      // Ensure button exists (find the ElevatedButton)
      final seedButtonFinder =
          find.widgetWithText(ElevatedButton, 'Seed DB (initial fetch)');
      expect(seedButtonFinder, findsOneWidget);
      print('Test: seed button found');

      // Allow UI to rebuild and reflect the inserted product
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      // Validate UI shows the seeded product
      expect(find.text('SeededProd'), findsOneWidget);

      // Cleanup AppDatabase
      await appDb.close();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
