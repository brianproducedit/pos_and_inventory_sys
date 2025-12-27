import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/analytics_events_dashboard_screen.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:fl_chart/fl_chart.dart';

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
  testWidgets('Chart tooltips appear on tap', (WidgetTester tester) async {
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

    expect(find.byType(BarChart), findsOneWidget);

    // Tap on the bar chart area near the left side to select the first bar
    // Locate the gesture area we added for the bar chart
    final barGestureFinder = find.byKey(const Key('barChartGesture'));
    expect(barGestureFinder, findsOneWidget);
    final barCenter = tester.getCenter(barGestureFinder);
    // Tap the gesture detector area (center) and then slightly left to hit bars
    await tester.tap(barGestureFinder);
    await tester.pumpAndSettle();
    await tester.tapAt(Offset(barCenter.dx - 40, barCenter.dy));
    await tester.pumpAndSettle();

    // Tooltip widget should appear
    expect(find.byKey(const Key('chartTooltip')), findsOneWidget);
    expect(find.textContaining('Store'), findsWidgets);

    // Now tap a sparkline (first LineChart) and ensure tooltip updates
    final lineFinder = find.byType(LineChart).first;
    final lineCenter = tester.getCenter(lineFinder);
    await tester.tapAt(lineCenter);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chartTooltip')), findsOneWidget);
    expect(find.textContaining('Store'), findsWidgets);
  });
}
