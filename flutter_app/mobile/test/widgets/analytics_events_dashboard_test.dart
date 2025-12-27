import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/analytics_events_dashboard_screen.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';

class _FakeAnalyticsProvider extends AnalyticsProvider {
  @override
  Future<Map<String, dynamic>> loadAnalyticsSummary(String eventName,
      {int? sinceDays,
      String? granularity,
      String? startDate,
      String? endDate,
      bool forceRefresh = false}) async {
    // return a response with series when granularity=daily
    if (granularity == 'daily' && sinceDays != null) {
      final labels = List.generate(sinceDays, (i) => 'd$i');
      return {
        'event_name': eventName,
        'total_count': 5,
        'avg_duration_ms': 150.0,
        'labels': labels,
        'by_store': [
          {
            'store_id': 1,
            'count': 3,
            'series': List.generate(sinceDays, (i) => (i + 1) % 4)
          },
          {
            'store_id': 2,
            'count': 2,
            'series': List.generate(sinceDays, (i) => (i + 2) % 3)
          },
        ],
      };
    }

    return {
      'event_name': eventName,
      'total_count': 5,
      'avg_duration_ms': 150.0,
      'by_store': [
        {'store_id': 1, 'count': 3},
        {'store_id': 2, 'count': 2}
      ],
    };
  }
}

class _FakeAuthProvider extends AuthProvider {
  final String? _role = 'superadmin';
  @override
  String? get role => _role;
}

class _FakeStoreProvider extends StoreProvider {
  @override
  List<Map<String, dynamic>> get myStores => [
        {'id': 1, 'name': 'Store 1', 'is_active': true}
      ];

  @override
  Map<String, dynamic>? get currentStore =>
      {'id': 1, 'name': 'Store 1', 'is_active': true};
}

void main() {
  testWidgets('Analytics Events Dashboard shows summary for superadmin',
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

    expect(find.text('Event: store_quick_switch'), findsOneWidget);
    expect(find.text('Total Events: 5'), findsOneWidget);
    expect(find.text('Average Duration (ms): 150.0'), findsOneWidget);
    expect(find.text('Store 1'), findsWidgets);

    // Chart should be present
    expect(find.byType(BarChart), findsOneWidget);

    // Ensure shared bottom navigation is present
    expect(find.byType(AppBottomNav), findsOneWidget);

    // Simulate selecting 7d range (default already 7d), ensure sparklines present
    expect(find.byType(LineChart), findsWidgets);
  });
}
