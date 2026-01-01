import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mobile/screens/pos_screen.dart';
import 'package:mobile/providers/pos_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'package:mobile/data/repositories/product_repository.dart';
import 'package:mobile/data/repositories/transaction_repository.dart';
import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    print('pos test: setUp start');
    initializeTestHelpersOnce();
    initSqfliteForTests();
    await DatabaseHelper.initTestDb();
    print('pos test: setUp completed');
  });

  tearDown(() async {
    await DatabaseHelper.resetTestDb();
  });

  // Skipped: flaky in widget harness; migrated to integration/e2e test in test/e2e/pos_checkout_e2e_test.dart
  // TODO: Remove this widget test once the e2e test is verified reliable.
  testWidgets('Checkout creates transaction, queue entry and updates stock',
      (WidgetTester tester) async {
    final db = DatabaseHelper();

    // Insert a product with stock 5
    final pid = await db.insertProduct(
        name: 'Checkout Widget',
        sku: 'CHK-1',
        price: 10.0,
        stockQuantity: 5,
        storeId: 1);
    print('pos test: inserted pid=$pid');

    final productRepo = ProductRepository(db: db);
    final txRepo = TransactionRepositoryImpl(db: db);

    final posProv = PosProvider(
        productRepository: productRepo, transactionRepository: txRepo);
    final auth = TestAuthProvider(roleValue: 'admin');
    final storeProv = TestStoreProvider();

    // Set store and preload products
    posProv.setStoreProvider(storeProv);
    print('pos test: about to query DB directly');
    try {
      final dbClient = await db.database;
      final raw = await dbClient.query('products');
      print('pos test: direct DB query returned ${raw.length} rows');
    } catch (e) {
      print('pos test: direct DB query failed: $e');
      rethrow;
    }

    print('pos test: about to call productRepo.getAllProducts directly');
    try {
      final prods = await productRepo
          .getAllProducts()
          .timeout(const Duration(seconds: 5));
      print('pos test: productRepo.getAllProducts returned ${prods.length}');
    } catch (e) {
      print('pos test: productRepo.getAllProducts timed out or failed: $e');
      rethrow;
    }

    print('pos test: about to call posProv.loadProducts');
    try {
      await posProv.loadProducts().timeout(const Duration(seconds: 5));
      print(
          'pos test: posProv.loadProducts completed, products=${posProv.availableProducts.length}');
    } catch (e) {
      print('pos test: posProv.loadProducts timed out or failed: $e');
      rethrow;
    }

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<StoreProvider>.value(value: storeProv),
        ChangeNotifierProvider<PosProvider>.value(value: posProv),
      ],
      child: const MaterialApp(home: PosScreen()),
    ));

    // Wait for product to render
    final productFinder = find.text('Checkout Widget');
    await tester.pumpAndSettle();
    expect(productFinder, findsOneWidget);

    // Tap Add button
    final addButton = find.widgetWithText(ElevatedButton, 'Add').first;
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    print('pos test: tapped Add, cart length=${posProv.cart.length}');

    // Open cart via AppBar button
    final cartButton = find.byTooltip('Open cart');
    expect(cartButton, findsOneWidget);
    await tester.tap(cartButton);
    await tester.pumpAndSettle();

    // In the cart dialog, tap Checkout button
    final checkoutButton = find.text('Checkout').last;
    expect(checkoutButton, findsOneWidget);
    await tester.tap(checkoutButton);
    await tester.pump();
    print('pos test: tapped cart Checkout, waiting for payment dialog');

    // Wait for payment dialog to appear
    final paymentEnd = DateTime.now().add(const Duration(seconds: 5));
    bool paymentShown = false;
    while (DateTime.now().isBefore(paymentEnd)) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Cash').evaluate().isNotEmpty) {
        paymentShown = true;
        break;
      }
    }
    expect(paymentShown, isTrue, reason: 'Payment dialog did not appear');

    // Payment method dialog - select Cash
    final cashTile = find.text('Cash');
    await tester.tap(cashTile);
    await tester.pumpAndSettle();
    print('pos test: tapped Cash, waiting for transaction');

    // Wait for transaction row to appear in DB (bounded polling)
    final end = DateTime.now().add(const Duration(seconds: 10));
    int loops = 0;
    int? txId;
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
      loops++;
      print('pos test: poll loop $loops');
      final dbClient = await db.database;
      final txs = await dbClient.query('transactions');
      if (txs.isNotEmpty) {
        txId = txs.first['id'] as int?;
        print('pos test: found txId=$txId');
        break;
      }
    }

    expect(txId, isNotNull,
        reason: 'Timed out waiting for transaction to be inserted');

    // Verify sync_queue has CREATE for transaction
    final dbClient = await db.database;
    final queue = await dbClient
        .query('sync_queue', where: 'row_id = ?', whereArgs: [txId]);
    expect(queue, isNotEmpty);
    expect(queue.first['action'], equals('CREATE'));
    expect(queue.first['table_name'], equals('transactions'));

    // Verify stock updated for product (was 5 -> 4)
    final prods = await (await db.database)
        .query('products', where: 'id = ?', whereArgs: [pid]);
    expect(prods.first['stock_quantity'], equals(4));
  }, skip: true, timeout: const Timeout(Duration(seconds: 60)));
}
