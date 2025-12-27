import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/analytics_events_dashboard_screen.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';

class _FakeAnalyticsProvider extends AnalyticsProvider {
  @override
  Future<Map<String, dynamic>> loadAnalyticsSummary(String eventName,
      {int? sinceDays,
      String? granularity,
      String? startDate,
      String? endDate,
      bool forceRefresh = false}) async {
    return {
      'event_name': eventName,
      'total_count': 7,
      'avg_duration_ms': 123.0,
      'by_store': [
        {'store_id': 1, 'count': 3},
        {'store_id': 2, 'count': 4}
      ],
    };
  }
}

class _FakeAuthProvider extends AuthProvider {
  String? _role = 'superadmin';
  @override
  String? get role => _role;
}

class _FakeStoreProvider extends StoreProvider {
  @override
  Map<String, dynamic>? get currentStore => null; // represent All Stores
}

void main() {
  testWidgets(
      'Analytics Dashboard shows All Stores indicator and aggregated data',
      (WidgetTester tester) async {
    final analytics = _FakeAnalyticsProvider();
    final auth = _FakeAuthProvider();
    final store = _FakeStoreProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AnalyticsProvider>.value(value: analytics),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<StoreProvider>.value(value: store),
        ],
        child: const MaterialApp(home: AnalyticsEventsDashboardScreen()),
      ),
    );

    await tester.pumpAndSettle();

    // Banner should be present
    expect(find.byKey(const Key('allStoresBanner')), findsOneWidget);
    expect(find.textContaining('All Stores'), findsWidgets);

    // Aggregated total should be shown
    expect(find.text('Total Events: 7'), findsOneWidget);
  });
}
