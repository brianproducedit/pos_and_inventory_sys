import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/pos_screen.dart';
import '../test_helpers.dart';
import 'package:mobile/providers/pos_provider.dart';
import 'package:mobile/providers/auth_provider.dart';

class FakePosProvider extends PosProvider {
  @override
  bool get isLoading => false;
  @override
  List<Map<String, dynamic>> get availableProducts => [
        {'id': 1, 'name': 'Apple', 'price': 1.5, 'stock_quantity': 10},
      ];

  @override
  Future<Map<String, dynamic>> processSale(String paymentMethod) async {
    // Simulate immediate successful sale and clear cart
    clearCart();
    return {'status': 'ok'};
  }
}

class FakeAuth extends AuthProvider {
  @override
  String? get role => 'admin';
}

void main() {
  testWidgets('Checkout button enables after add and processes sale',
      (tester) async {
    final pos = FakePosProvider();
    final auth = FakeAuth();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<PosProvider>.value(value: pos),
      ],
      child: wrapWithDefaultProviders(const PosScreen(), auth: auth),
    ));

    await tester.pumpAndSettle();

    // Initially Checkout should be disabled
    final checkoutFinder = find.widgetWithText(ElevatedButton, 'Checkout');
    expect(checkoutFinder, findsOneWidget);
    final checkoutBtn = tester.widget<ElevatedButton>(checkoutFinder);
    expect(checkoutBtn.onPressed, isNull);

    // Add product
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
    await tester.pumpAndSettle();

    // Open cart
    await tester.tap(find.byIcon(Icons.shopping_cart));
    await tester.pumpAndSettle();

    // Checkout in dialog should be enabled (PrimaryButton -> ElevatedButton)
    final dialogCheckout = find.widgetWithText(ElevatedButton, 'Checkout');
    expect(dialogCheckout, findsWidgets);

    // Tap Checkout and choose Cash
    await tester.tap(dialogCheckout.last);
    await tester.pumpAndSettle();

    // Payment method dialog should appear; tap 'Cash'
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    // After processing sale, success snackbar should appear
    expect(find.text('Sale completed successfully!'), findsOneWidget);
  });
}
