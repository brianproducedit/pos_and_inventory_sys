import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/pos_screen.dart';
import 'package:mobile/providers/pos_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/data/repositories/product_repository.dart';
import 'package:mobile/domain/models/product.dart';
import 'package:mobile/data/local/database_helper.dart';

import '../test_helpers.dart';

class FakePosProvider extends PosProvider {
  @override
  bool get isLoading => false;
  @override
  List<Map<String, dynamic>> get availableProducts => [
        {'id': 1, 'name': 'Apple', 'price': 1.5, 'stock_quantity': 10},
        {'id': 2, 'name': 'Banana', 'price': 0.5, 'stock_quantity': 5},
      ];
}

class FakeAuth extends AuthProvider {
  @override
  String? get role => 'admin';
}

// Fake repository used by widget tests to avoid touching Sqlite
class SimpleFakeRepo {
  Future<List<Map<String, dynamic>>> getAllProducts() async => [
        {
          'id': 1,
          'name': 'Repo Product A',
          'price': 2.5,
          'stock_quantity': 3,
          'store_id': 1
        },
        {
          'id': 2,
          'name': 'Repo Product B',
          'price': 3.5,
          'stock_quantity': 7,
          'store_id': 2
        }
      ];
}

// ProductRepository-compatible fake that maps fake rows to Product domain objects
class ProductRepoFake extends ProductRepository {
  ProductRepoFake() : super(db: DatabaseHelper());

  @override
  Future<List<Product>> getAllProducts() async {
    final items = await SimpleFakeRepo().getAllProducts();
    return items.map((m) => Product.fromMap(m)).toList();
  }
}

void main() {
  testWidgets('POS adds product to cart and checkout enabled', (tester) async {
    final pos = FakePosProvider();
    final auth = FakeAuth();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<PosProvider>.value(value: pos),
      ],
      child: wrapWithDefaultProviders(const PosScreen(), auth: auth),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('\$1.50'), findsOneWidget);

    // Tap add on Apple
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add').first);
    await tester.pumpAndSettle();

    // Cart icon should be enabled (tap to open)
    await tester.tap(find.byIcon(Icons.shopping_cart));
    await tester.pumpAndSettle();

    expect(find.textContaining('Total:'), findsWidgets);
  });

  testWidgets('POS shows repository products and responds to store context',
      (tester) async {
    final repo = ProductRepoFake();
    final pos = PosProvider(productRepository: repo);
    final auth = TestAuthProvider(roleValue: 'admin');

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<PosProvider>.value(value: pos),
      ],
      child: wrapWithDefaultProviders(const PosScreen(), auth: auth),
    ));

    // Ensure provider picks up store context (TestStoreProvider.currentStore -> id:1)
    await tester.pumpAndSettle();

    // Expect product from store 1 to be visible
    expect(find.text('Repo Product A'), findsOneWidget);
    expect(find.text('Repo Product B'), findsNothing);
  });
}
