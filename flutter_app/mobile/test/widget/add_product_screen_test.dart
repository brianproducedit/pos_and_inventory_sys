import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/add_product_screen.dart';
import 'package:mobile/widgets/primary_text_field.dart';
import 'package:mobile/widgets/primary_button.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/inventory_provider.dart';

class TestAuth extends AuthProvider {
  @override
  String? get role => 'admin';
}

class TestStore extends StoreProvider {
  @override
  Map<String, dynamic>? get currentStore => {'id': 1, 'name': 'Test Store'};
}

class TestInventory extends InventoryProvider {
  @override
  Future<void> addProduct(Map<String, dynamic> productData) async {
    // simulate success
  }
}

void main() {
  testWidgets('AddProductScreen uses PrimaryTextField and PrimaryButton',
      (WidgetTester tester) async {
    final auth = TestAuth();
    final store = TestStore();
    final inv = TestInventory();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<StoreProvider>.value(value: store),
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
      ],
      child: const MaterialApp(home: AddProductScreen()),
    ));

    await tester.pumpAndSettle();

    expect(find.byType(PrimaryTextField), findsNWidgets(4));
    expect(find.byType(PrimaryButton), findsOneWidget);
  });
}
