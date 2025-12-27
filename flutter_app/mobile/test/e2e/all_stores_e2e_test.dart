import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/screens/analytics_screen.dart';
import 'package:mobile/screens/analytics_events_dashboard_screen.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/services/store_service.dart';
import 'package:mobile/services/sales_service.dart';
import 'package:mobile/services/analytics_service.dart';

// Test helpers: keep classes at top-level (Dart disallows class declarations inside functions)
class FakeAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => true;

  @override
  String? get role => 'superadmin';

  @override
  Future<void> checkAuthStatus() async {
    // no-op for tests
  }
}

class FakeSalesService extends SalesService {
  @override
  Future<Map<String, dynamic>> getSalesAnalytics({int? storeId}) async {
    if (storeId == null) {
      return {
        'total_sales': 100,
        'total_revenue': 1000.0,
        'average_sale': 10.0,
        'daily_sales': []
      };
    }
    return {
      'total_sales': 40,
      'total_revenue': 400.0,
      'average_sale': 10.0,
      'daily_sales': []
    };
  }
}

class FakeStoreService extends StoreService {
  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async {
    if (storeId == 0) return {'current_store': null};
    return {
      'current_store': {'id': storeId, 'name': 'Store $storeId'}
    };
  }

  @override
  Future<Map<String, dynamic>> getCurrentStore() async {
    return {
      'current_store': {'id': 1, 'name': 'Store 1'}
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getStores() async {
    return [
      {'id': 0, 'name': 'All Stores', 'is_active': true, 'is_all': true},
      {'id': 1, 'name': 'Store 1', 'is_active': true},
      {'id': 2, 'name': 'Store 2', 'is_active': true},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getMyStores() async {
    return [
      {'id': 1, 'name': 'Store 1', 'is_active': true},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getAvailableStores() async {
    // Available stores for quick action; include All Stores
    return [
      {'id': 0, 'name': 'All Stores', 'is_active': true, 'is_all': true},
      {'id': 1, 'name': 'Store 1', 'is_active': true},
      {'id': 2, 'name': 'Store 2', 'is_active': true},
    ];
  }
}

class FakeAnalyticsService extends AnalyticsService {
  @override
  Future<Map<String, dynamic>> getAnalyticsSummary(String eventName,
      {int? sinceDays,
      String? granularity,
      String? startDate,
      String? endDate}) async {
    return {
      'event_name': eventName,
      'total_count': 100,
      'avg_duration_ms': 10,
      'by_store': [
        {'store_id': null, 'count': 100, 'series': []},
      ],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('E2E-like: switch to All Stores and show aggregated sales',
      (WidgetTester tester) async {
    final fakeAuth = FakeAuthProvider();
    final storeProvider = StoreProvider(storeService: FakeStoreService());
    final analyticsProvider = AnalyticsProvider(
      salesService: FakeSalesService(),
      analyticsService: FakeAnalyticsService(),
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: fakeAuth),
        ChangeNotifierProvider<StoreProvider>.value(value: storeProvider),
        ChangeNotifierProvider<AnalyticsProvider>.value(
            value: analyticsProvider),
      ],
      child: MaterialApp(
        routes: {
          '/': (context) => const HomeScreen(),
          '/home': (context) => const HomeScreen(),
          '/analytics': (context) => const AnalyticsScreen(),
          '/analytics/events': (context) =>
              const AnalyticsEventsDashboardScreen(),
        },
        initialRoute: '/home',
      ),
    ));

    await tester.pumpAndSettle();

    await storeProvider.initialize();
    // Provide analytics provider context (auth + store) so summary loads correctly
    analyticsProvider.setAuthProvider(fakeAuth);
    analyticsProvider.setStoreProvider(storeProvider);
    await tester.pumpAndSettle();

    // Open quick action, select 'All Stores'
    final quickAction = find.widgetWithIcon(IconButton, Icons.store);
    expect(quickAction, findsOneWidget);
    await tester.tap(quickAction);
    await tester.pumpAndSettle();

    expect(find.text('All Stores'), findsOneWidget);
    await tester.tap(find.text('All Stores'));
    await tester.pumpAndSettle();

    // Navigate to analytics
    final analyticsButton = find.widgetWithIcon(IconButton, Icons.analytics);
    expect(analyticsButton, findsOneWidget);
    await tester.tap(analyticsButton);
    await tester.pumpAndSettle();

    // Open Events Dashboard via FAB to see All Stores banner
    final eventsFab =
        find.widgetWithText(FloatingActionButton, 'Events Dashboard');
    expect(eventsFab, findsOneWidget);
    await tester.tap(eventsFab);
    await tester.pumpAndSettle();

    // All Stores banner should be visible on the Events Dashboard
    expect(find.byKey(const Key('allStoresBanner')), findsOneWidget);

    // Go back to Analytics Overview and verify aggregated 'Total Sales' metric
    final backButton = find.byTooltip('Back');
    expect(backButton, findsOneWidget);
    await tester.tap(backButton);
    await tester.pumpAndSettle();

    // Verify aggregated total sales value is visible (title text may vary by layout)
    expect(find.text('100'), findsOneWidget);
  });
}
