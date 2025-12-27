import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/screens/home_screen.dart';
import '../test_helpers.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/inventory_provider.dart';

class FakeAnalyticsProvider extends AnalyticsProvider {
  @override
  bool get isLoading => false;

  @override
  Map<String, dynamic> get salesData =>
      {'total_sales': 5, 'total_revenue': 123.45, 'average_sale': 24.69};
}

class FakeInventoryProvider extends InventoryProvider {
  @override
  int get lowStockCount => 2;

  @override
  int get criticalLowStockCount => 1;
}

class FakeAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  String? get role => 'admin';
}

void main() {
  testWidgets('Home summary uses MetricCard and shows low stock',
      (tester) async {
    final analytics = FakeAnalyticsProvider();
    final inventory = FakeInventoryProvider();

    final auth = FakeAuthProvider();

    await tester.pumpWidget(wrapWithDefaultProviders(const HomeScreen(),
        auth: auth, analytics: analytics, inventory: inventory));

    await tester.pumpAndSettle();

    expect(find.text('Today\'s Summary'), findsOneWidget);
    expect(find.text('5'), findsOneWidget); // total sales
    expect(find.textContaining('\$123.45'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // low stock
  });
}
