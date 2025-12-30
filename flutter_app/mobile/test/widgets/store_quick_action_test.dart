import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/models/database_models.dart';

class _FakeAuthProvider extends AuthProvider {
  String? _fakeRole;
  int? _fakeUserId;

  @override
  String? get role => _fakeRole;

  @override
  User? get user => _fakeUserId != null
      ? User(
          id: _fakeUserId!,
          username: 'test',
          passwordHash: '',
          role: _fakeRole ?? 'admin',
          storeId: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        )
      : null;

  void setRole(String r) {
    _fakeRole = r;
    notifyListeners();
  }

  void setUserId(int id) {
    _fakeUserId = id;
    notifyListeners();
  }
}

class _FakeStoreProvider extends StoreProvider {
  @override
  bool get isSwitchingStore => false;

  List<Map<String, dynamic>> _stores = [];
  @override
  List<Map<String, dynamic>> get availableStores => _stores;

  @override
  Future<void> loadAvailableStores() async {
    _stores = [
      {'id': 1, 'name': 'Alpha'},
      {'id': 2, 'name': 'Beta'}
    ];
  }

  @override
  Future<bool> switchStore(Map<String, dynamic> store) async {
    // simulate success
    return true;
  }
}

class _FakeStoreProviderNoStores extends StoreProvider {
  @override
  bool get isSwitchingStore => false;

  List<Map<String, dynamic>> _stores = [];
  @override
  List<Map<String, dynamic>> get availableStores => _stores;

  @override
  Future<void> loadAvailableStores() async {
    // Simulate no assigned stores (admin fallback case)
    _stores = [];
  }

  @override
  Future<bool> switchStore(Map<String, dynamic> store) async {
    // simulate success
    return true;
  }
}

void main() {
  testWidgets('quick action visible for admin and can open dialog',
      (WidgetTester tester) async {
    final storeProv = _FakeStoreProvider();
    final authProv = _FakeAuthProvider();
    authProv.setRole('admin');
    authProv.setUserId(99);
    final fakeAnalytics = AnalyticsProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StoreProvider>.value(value: storeProv),
          ChangeNotifierProvider<AuthProvider>.value(value: authProv),
          ChangeNotifierProvider<AnalyticsProvider>.value(value: fakeAnalytics),
        ],
        child: MaterialApp(
            home:
                Scaffold(appBar: AppBar(actions: const [StoreQuickAction()]))),
      ),
    );

    expect(find.byIcon(Icons.store), findsOneWidget);

    await tester.tap(find.byIcon(Icons.store));
    await tester.pumpAndSettle();

    expect(find.text('Switch Store'), findsOneWidget);
    // Admin has assigned stores in this fake provider so 'All Stores' should be shown but disabled
    expect(find.text('All Stores'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    // Attempt to tap the disabled All Stores option — dialog should remain open
    await tester.tap(find.text('All Stores'));
    await tester.pumpAndSettle();
    // Dialog remains visible
    expect(find.text('Switch Store'), findsOneWidget);

    // Select Alpha and assert analytics event emitted
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    // The fake analytics provider should have recorded the event
    final analytics = Provider.of<AnalyticsProvider>(
        tester.element(find.byType(StoreQuickAction)),
        listen: false);
    expect(analytics.lastEventName, 'store_quick_switch');
    final payload = analytics.lastEventPayload;
    expect(payload, isNotNull);
    expect(payload!['userId'], 99);
    expect(payload['toStoreId'], 1);
    expect(payload['durationMs'], isA<int>());
    expect(payload['success'], true);
  });

  testWidgets('admin with no assigned stores sees All Stores option',
      (WidgetTester tester) async {
    final storeProv = _FakeStoreProviderNoStores();
    final authProv = _FakeAuthProvider();
    authProv.setRole('admin');
    authProv.setUserId(100);
    final fakeAnalytics = AnalyticsProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StoreProvider>.value(value: storeProv),
          ChangeNotifierProvider<AuthProvider>.value(value: authProv),
          ChangeNotifierProvider<AnalyticsProvider>.value(value: fakeAnalytics),
        ],
        child: MaterialApp(
            home:
                Scaffold(appBar: AppBar(actions: const [StoreQuickAction()]))),
      ),
    );

    await tester.tap(find.byIcon(Icons.store));
    await tester.pumpAndSettle();

    expect(find.text('Switch Store'), findsOneWidget);
    // No assigned stores -> All Stores option should be present
    expect(find.text('All Stores'), findsOneWidget);

    await tester.tap(find.text('All Stores'));
    await tester.pumpAndSettle();

    final analytics = Provider.of<AnalyticsProvider>(
        tester.element(find.byType(StoreQuickAction)),
        listen: false);
    expect(analytics.lastEventName, 'store_quick_switch');
    final payload = analytics.lastEventPayload;
    expect(payload, isNotNull);
    expect(payload!['userId'], 100);
    expect(payload['toStoreId'], 0);
    expect(payload['success'], true);
  });
}
