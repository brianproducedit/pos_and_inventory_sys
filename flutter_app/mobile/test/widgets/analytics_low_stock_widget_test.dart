import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/metric_card.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/analytics_screen.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/inventory_provider.dart';

class _FakeAuthProvider extends AuthProvider {
  String? _fakeRole = 'admin';

  @override
  String? get role => _fakeRole;
}

class _FakeStoreProvider extends StoreProvider {
  @override
  bool get isInitialized => true;

  @override
  Map<String, dynamic>? get currentStore => null;
}

class _FakeInventoryProvider extends InventoryProvider {
  @override
  List<Map<String, dynamic>> get lowStockAlerts => [
        {'id': 1, 'name': 'P1', 'stock_quantity': 3, 'alert_level': 'Critical'}
      ];

  @override
  int get lowStockCount => lowStockAlerts.length;
}

class _FakeAnalyticsProvider extends AnalyticsProvider {
  @override
  Future<void> loadAnalyticsForCurrentStore() async {
    // No-op to avoid network calls during widget test
    return;
  }

  @override
  bool get isLoading => false;

  @override
  Map<String, dynamic> get salesData => {
        'total_sales': 0,
        'total_revenue': 0.0,
        'average_sale': 0.0,
        'daily_sales': []
      };

  @override
  List<Map<String, dynamic>> get inventoryAlerts => [];
}

void main() {
  testWidgets('Analytics overview shows low stock count from InventoryProvider',
      (WidgetTester tester) async {
    final auth = _FakeAuthProvider();
    final store = _FakeStoreProvider();
    final analytics = _FakeAnalyticsProvider();
    final inventory = _FakeInventoryProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<StoreProvider>.value(value: store),
          ChangeNotifierProvider<AnalyticsProvider>.value(value: analytics),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
        ],
        child: const MaterialApp(home: AnalyticsScreen()),
      ),
    );

    // Allow async init to run
    await tester.pumpAndSettle();

    // Metric card should be present (title sometimes rendered differently in different layouts)
    expect(find.byType(MetricCard), findsWidgets);
    expect(find.text('1'), findsOneWidget);
  });
}
