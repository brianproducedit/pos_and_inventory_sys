import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/analytics_events_dashboard_screen.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';

class _FakeAnalyticsProviderMany extends AnalyticsProvider {
  @override
  Future<Map<String, dynamic>> loadAnalyticsSummary(String eventName,
      {int? sinceDays,
      String? granularity,
      String? startDate,
      String? endDate,
      bool forceRefresh = false}) async {
    // many stores to increase content
    final stores = List.generate(
        12,
        (i) => {
              'store_id': i + 1,
              'count': (i + 1) * 2,
              'series': List.generate(7, (j) => j + i)
            });
    return {
      'event_name': eventName,
      'total_count': 123,
      'avg_duration_ms': 321.0,
      'by_store': stores,
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
  testWidgets('Analytics Dashboard does not overflow on narrow/short view',
      (WidgetTester tester) async {
    final analytics = _FakeAnalyticsProviderMany();
    final auth = _FakeAuthProvider();
    final store = _FakeStoreProvider();

    // small viewport
    const width = 360.0;
    const height = 320.0;
    tester.binding.window.physicalSizeTestValue = const Size(width, height);
    tester.binding.window.devicePixelRatioTestValue = 1.0;

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

    // No render overflow errors should have been thrown
    final exception = tester.takeException();
    expect(exception, isNull,
        reason: 'No exceptions (including layout overflows) should occur');

    // Banner and list should be present
    expect(find.byKey(const Key('allStoresBanner')), findsOneWidget);
    expect(find.textContaining('Total Events:'), findsOneWidget);

    // On narrow view the banner should hide the small hint text to avoid overflow
    expect(find.text('Aggregated'), findsNothing);

    // Restore window
    tester.binding.window.clearPhysicalSizeTestValue();
    tester.binding.window.clearDevicePixelRatioTestValue();
  });
}
