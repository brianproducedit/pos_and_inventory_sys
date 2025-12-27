import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/analytics_screen.dart';
import '../test_helpers.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/inventory_provider.dart';

class FakeAnalyticsProvider extends AnalyticsProvider {
  @override
  bool get isLoading => false;

  @override
  Map<String, dynamic> get salesData => {
        'total_sales': 7,
        'total_revenue': 321.0,
        'average_sale': 45.86,
        'daily_sales': [
          {'date': '2025-12-20', 'revenue': 50.0},
          {'date': '2025-12-21', 'revenue': 80.0},
          {'date': '2025-12-22', 'revenue': 120.0},
        ]
      };

  @override
  List<Map<String, dynamic>> get topProducts => [
        {'name': 'Widget', 'revenue': 120.0, 'sales_count': 10},
      ];

  @override
  List<Map<String, dynamic>> get recentSales => [
        {
          'id': 1,
          'items_count': 2,
          'total_amount': 12.0,
          'created_at': '2025-12-22'
        }
      ];
}

class FakeAuth extends AuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  String? get role => 'admin';
}

class FakeInventory extends InventoryProvider {
  @override
  int get lowStockCount => 1;
}

void main() {
  testWidgets('Analytics screen shows key metrics and top products',
      (tester) async {
    final analytics = FakeAnalyticsProvider();
    final auth = FakeAuth();
    final inventory = FakeInventory();

    await tester.pumpWidget(wrapWithDefaultProviders(const AnalyticsScreen(),
        analytics: analytics, auth: auth, inventory: inventory));

    await tester.pumpAndSettle();

    expect(find.text('Key Metrics'), findsOneWidget);
    expect(find.text('7'), findsOneWidget); // total sales
    expect(find.textContaining('\$321.00'), findsOneWidget);

    // Switch to Sales tab to view top products
    await tester.tap(find.text('Sales'));
    await tester.pumpAndSettle();

    expect(find.text('Top Products'), findsOneWidget);
    expect(find.text('Widget'), findsOneWidget);
  });
}
