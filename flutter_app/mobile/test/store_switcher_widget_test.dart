import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/widgets/store_switcher_v2.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/analytics_provider.dart';

import 'package:mobile/providers/auth_provider.dart';

class TestAuthProvider extends AuthProvider {
  final String testRole;
  TestAuthProvider(this.testRole);
  @override
  String? get role => testRole;
}

class TestAnalyticsProvider extends AnalyticsProvider {
  int lastLoadedStoreId = -1;

  @override
  Future<void> loadAnalytics({int? storeId}) async {
    lastLoadedStoreId = storeId ?? -1;
    // avoid network call
    return;
  }
}

class FakeStoreProvider with ChangeNotifier {
  List<Map<String, dynamic>> myStores = [];
  Map<String, dynamic>? currentStore;
  bool _isSwitching = false;

  bool get isSwitchingStore => _isSwitching;

  Future<bool> switchStore(Map<String, dynamic> store) async {
    _isSwitching = true;
    notifyListeners();
    // simulate network
    await Future<void>.delayed(const Duration(milliseconds: 10));
    currentStore = {'id': store['id'], 'name': 'Fake Store ${store['id']}'};
    _isSwitching = false;
    notifyListeners();
    return true;
  }
}

class TestStoreProvider extends StoreProvider {
  List<Map<String, dynamic>> testMyStores = [];
  Map<String, dynamic>? testCurrentStore;
  bool _isSwitchingLocal = false;

  @override
  List<Map<String, dynamic>> get myStores => testMyStores;

  @override
  Map<String, dynamic>? get currentStore => testCurrentStore;

  @override
  bool get isSwitchingStore => _isSwitchingLocal;

  @override
  Future<bool> switchStore(Map<String, dynamic> store) async {
    _isSwitchingLocal = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // If switching to All Stores (id == 0), represent global view by null
    testCurrentStore = store['id'] == 0
        ? null
        : {'id': store['id'], 'name': 'Fake Store ${store['id']}'};
    _isSwitchingLocal = false;
    notifyListeners();
    return true;
  }
}

void main() {
  testWidgets('StoreSwitcher shows stores and can switch', (tester) async {
    final fakeStore = FakeStoreProvider();
    fakeStore.myStores = [
      {'id': 1, 'name': 'Store A', 'location': 'Loc A', 'is_active': true},
      {'id': 2, 'name': 'Store B', 'location': 'Loc B', 'is_active': true},
    ];
    fakeStore.currentStore = fakeStore.myStores.first;
    final fakeAnalytics = TestAnalyticsProvider();

    // Create test-compatible providers
    final testStore = TestStoreProvider()
      ..testMyStores = fakeStore.myStores
      ..testCurrentStore = fakeStore.currentStore;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
              create: (_) => TestAuthProvider('admin')),
          ChangeNotifierProvider<StoreProvider>(create: (_) => testStore),
          ChangeNotifierProvider<AnalyticsProvider>(
              create: (_) => fakeAnalytics),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(),
            body: const Center(child: StoreSwitcher()),
          ),
        ),
      ),
    );

    // Expect to see the current store name
    expect(find.text('Store A'), findsOneWidget);

    // Open popup menu
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();

    // All Stores option should be present for admin
    expect(find.text('All Stores'), findsOneWidget);

    // Tap on Store B menu item
    expect(find.text('Store B'), findsOneWidget);
    await tester.tap(find.text('Store B').first);
    await tester.pumpAndSettle();

    // Confirmation dialog should appear
    expect(find.text('Switch Store'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Switch'));
    await tester.pumpAndSettle();

    // After switch completes, StoreProvider.currentStore should be updated
    expect(testStore.currentStore!['id'], 2);
    // Analytics should have been reloaded for store id 2
    expect(fakeAnalytics.lastLoadedStoreId, 2);

    // Now switch to All Stores
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();

    await tester.tap(find.text('All Stores'));
    await tester.pumpAndSettle();
    expect(find.text('Switch Store'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Switch'));
    await tester.pumpAndSettle();

    // After switching to all stores, currentStore should be null
    expect(testStore.currentStore, isNull);
    // Analytics should have been reloaded for all stores (null -> -1 in fake)
    expect(fakeAnalytics.lastLoadedStoreId, -1);
  });
}
