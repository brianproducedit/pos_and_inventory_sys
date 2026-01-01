import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../test_helpers.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/data/repositories/product_repository.dart';
import 'package:mobile/data/repositories/transaction_repository.dart';
import 'package:mobile/providers/pos_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/data/local/database_helper.dart';

// Lightweight test-only StoreProvider to avoid network calls during e2e/provider tests
class TestStoreProvider extends StoreProvider {
  final Map<String, dynamic> _s;
  TestStoreProvider(this._s) : super();

  @override
  Map<String, dynamic>? get currentStore => _s;

  @override
  void addListener(listener) {}

  @override
  void removeListener(listener) {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Use shared test bootstrap for cross-environment compatibility
    initSqfliteForTests();

    // Initialize an in-memory DB for this test run
    await DatabaseHelper.initTestDb();

    // Ensure an active authenticated user and store
    SharedPreferences.setMockInitialValues({
      'access_token': 'dummy_token',
      'user_role': 'admin',
      'current_store_id': 1
    });
  });

  tearDown(() async {
    await DatabaseHelper.resetTestDb();
  });

  testWidgets(
      'POS checkout end-to-end: creates transaction, enqueues sync, updates stock',
      (WidgetTester tester) async {
    final db = DatabaseHelper();

    // Insert product with stock 5
    final pid = await db.insertProduct(
        name: 'E2E Checkout',
        sku: 'E2E-CHK-1',
        price: 10.0,
        stockQuantity: 5,
        storeId: 1);

    // Use repositories and provider directly to perform the sale (more deterministic than driving full UI)
    final productRepo = ProductRepository(db: db);
    final txRepo = TransactionRepositoryImpl(db: db);

    // Use top-level TestStoreProvider to avoid network calls during e2e/provider tests
    final posProv = PosProvider(
        productRepository: productRepo, transactionRepository: txRepo);
    posProv
        .setStoreProvider(TestStoreProvider({'id': 1, 'name': 'Test Store'}));

    final products = await productRepo.getAllProducts();
    expect(products.length, greaterThanOrEqualTo(1),
        reason: 'No product rows found in DB');

    // Add first product to cart and process sale
    final first = products.first.toMap();
    posProv.addToCart(first, 1);
    final res = await posProv.processSale('Cash');
    final txId =
        (res['transaction_id'] is int) ? res['transaction_id'] as int : null;

    expect(txId, isNotNull,
        reason: 'processSale did not return a transaction id');

    // Verify sync_queue has CREATE for this transaction (with diagnostics)
    final dbClient = await db.database;
    final txQueueRows = await dbClient.query('sync_queue',
        where: 'table_name = ?',
        whereArgs: ['transactions'],
        orderBy: 'created_at DESC');
    print('E2E DEBUG: tx queue rows = $txQueueRows');
    final matching = txQueueRows.where((r) => r['row_id'] == txId).toList();
    expect(matching, isNotEmpty,
        reason:
            'No sync_queue entry found for transaction id=$txId. All transaction queue rows: $txQueueRows');
    expect(matching.first['action'], equals('CREATE'));

    // Verify stock updated (5 -> 4)
    final dbProds =
        await dbClient.query('products', where: 'id = ?', whereArgs: [pid]);
    expect(dbProds.first['stock_quantity'], equals(4));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
