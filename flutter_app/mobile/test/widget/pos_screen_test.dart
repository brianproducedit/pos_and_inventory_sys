import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/pos_screen.dart';
import 'package:mobile/providers/pos_provider.dart';
import 'package:mobile/providers/auth_provider.dart';

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
}
