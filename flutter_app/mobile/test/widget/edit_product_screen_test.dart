import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/edit_product_screen.dart';
import 'package:mobile/providers/inventory_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/data/remote/postgres_api_service.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'package:mobile/data/repositories/product_repository.dart';
import 'package:mobile/domain/models/product.dart';

class FakeProductRepo implements ProductRepository {
  @override
  final DatabaseHelper db = DatabaseHelper();
  @override
  final PostgresApiService? api = null;

  bool updateCalled = false;
  bool deleteCalled = false;
  Map<String, dynamic>? lastUpdatedFields;

  @override
  Future<int> addProduct(Product product) async => 1;

  @override
  Future<List<Product>> getAllProducts({int? storeId}) async => [];

  @override
  Future<int> updateStock(int localProductId, int newQuantity) async => 1;

  @override
  Future<int> updateProduct(
      int localProductId, Map<String, dynamic> fields) async {
    updateCalled = true;
    lastUpdatedFields = fields;
    return 1;
  }

  @override
  Future<int> deleteProduct(int localProductId) async {
    deleteCalled = true;
    return 1;
  }
}

/// Test-only auth provider that returns admin role
class TestAuthProvider extends AuthProvider {
  @override
  String? get role => 'admin';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EditProductScreen UI flows', () {
    testWidgets('Update button triggers repository update', (tester) async {
      final fakeRepo = FakeProductRepo();
      final inventory = InventoryProvider(productRepository: fakeRepo);
      inventory.setCurrentStoreForTest({'id': 1, 'name': 'Test Store'});

      final product = {
        'id': 123,
        'name': 'Old Name',
        'price': 5.0,
        'stock_quantity': 2,
        'description': 'Old desc',
        'is_active': true
      };

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
              create: (_) => TestAuthProvider()),
          ChangeNotifierProvider<InventoryProvider>(create: (_) => inventory),
        ],
        child: MaterialApp(home: EditProductScreen(product: product)),
      ));

      // Verify initial UI shows values
      expect(find.text('Old Name'), findsOneWidget);
      expect(find.text('Current: \$5.00'), findsOneWidget);

      // Enter new name and price
      await tester.enterText(find.byType(TextFormField).at(0), 'New Name');
      await tester.enterText(find.byType(TextFormField).at(1), '10.5');
      await tester.enterText(find.byType(TextFormField).at(2), '4');
      await tester.pumpAndSettle();

      // Ensure the button is visible (form may be scrollable)
      await tester.ensureVisible(find.text('Update Product'));

      // Tap update
      await tester.tap(find.text('Update Product'));
      await tester.pumpAndSettle();

      expect(fakeRepo.updateCalled, isTrue);
      expect(fakeRepo.lastUpdatedFields, isNotNull);
      expect(fakeRepo.lastUpdatedFields!['name'], 'New Name');
      expect(fakeRepo.lastUpdatedFields!['price'], 10.5);
      expect(fakeRepo.lastUpdatedFields!['stock_quantity'], 4);

      // Screen should have been popped after successful update
      expect(find.byType(EditProductScreen), findsNothing);
    });

    testWidgets('Delete icon and confirmation triggers repository delete',
        (tester) async {
      final fakeRepo = FakeProductRepo();
      final inventory = InventoryProvider(productRepository: fakeRepo);
      inventory.setCurrentStoreForTest({'id': 1, 'name': 'Test Store'});

      final product = {
        'id': 321,
        'name': 'ToDelete',
        'price': 2.0,
        'stock_quantity': 1,
        'description': '',
        'is_active': true
      };

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
              create: (_) => TestAuthProvider()),
          ChangeNotifierProvider<InventoryProvider>(create: (_) => inventory),
        ],
        child: MaterialApp(home: EditProductScreen(product: product)),
      ));

      // Tap delete icon in app bar
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      // Confirm dialog is shown
      expect(find.text('Delete Product'), findsOneWidget);

      // Tap Delete in dialog
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(fakeRepo.deleteCalled, isTrue);
      // Screen should have been popped after successful delete
      expect(find.byType(EditProductScreen), findsNothing);
    });
  });
}
