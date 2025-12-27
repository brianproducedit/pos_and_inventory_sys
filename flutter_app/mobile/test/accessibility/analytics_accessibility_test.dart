import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/inventory_provider.dart';
import 'package:mobile/widgets/metric_card.dart';
import 'package:mobile/screens/analytics_screen.dart';
import '../test_helpers.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';

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
        ]
      };
}

class FakeAuth extends AuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  String? get role => 'admin';
}

void main() {
  testWidgets('Analytics is accessible and shows main headings',
      (tester) async {
    final analytics = FakeAnalyticsProvider();
    final auth = FakeAuth();

    await tester.pumpWidget(wrapWithDefaultProviders(const AnalyticsScreen(),
        analytics: analytics,
        auth: auth,
        inventory: InventoryProvider(),
        store: StoreProvider()));

    await tester.pumpAndSettle();

    expect(find.text('Key Metrics'), findsOneWidget);
    expect(find.byType(MetricCard), findsWidgets);
    expect(find.text('7'), findsOneWidget); // total sales value
  });
}
