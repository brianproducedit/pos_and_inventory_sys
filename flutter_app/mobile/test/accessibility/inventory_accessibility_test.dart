import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/inventory_screen.dart';
import '../test_helpers.dart';
import 'package:mobile/providers/inventory_provider.dart';
import 'package:mobile/providers/auth_provider.dart';

class FakeInventoryProvider extends InventoryProvider {
  @override
  bool get isLoading => false;
  @override
  List<Map<String, dynamic>> get products => [
        {
          'id': 1,
          'name': 'Widget',
          'price': 3.0,
          'stock_quantity': 2,
          'is_active': true
        },
      ];
  @override
  List<Map<String, dynamic>> get lowStockAlerts => [
        {'product_name': 'Widget', 'stock_quantity': 2}
      ];
  @override
  int get lowStockCount => 1;
  @override
  int get criticalLowStockCount => 0;
}

class FakeAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => true;

  @override
  String? get role => 'admin';
}

void main() {
  testWidgets('LowStockPanel is accessible and View button present',
      (tester) async {
    final inventory = FakeInventoryProvider();

    final auth = FakeAuthProvider();

    await tester.pumpWidget(wrapWithDefaultProviders(const InventoryScreen(),
        inventory: inventory, auth: auth));

    await tester.pumpAndSettle();

    expect(find.textContaining('low stock'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
  });
}
