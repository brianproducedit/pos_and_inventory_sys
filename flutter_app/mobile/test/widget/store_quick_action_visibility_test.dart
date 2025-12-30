import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/services/store_service.dart';
import '../test_helpers.dart';

class TestAuthCashier extends AuthProvider {
  @override
  bool get isAuthenticated => true;

  @override
  String? get role => 'cashier';
}

class TestAuthAdmin extends AuthProvider {
  @override
  bool get isAuthenticated => true;

  @override
  String? get role => 'admin';
}

class FakeStoreServiceForUI extends StoreService {
  @override
  Future<List<Map<String, dynamic>>> getAvailableStores() async {
    return [
      {'id': 0, 'name': 'All Stores', 'is_all': true},
      {'id': 1, 'name': 'Store 1'},
    ];
  }

  @override
  Future<Map<String, dynamic>> getCurrentStore() async {
    return {
      'current_store': {'id': 1, 'name': 'Store 1'}
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getMyStores() async {
    return [
      {'id': 1, 'name': 'Store 1'}
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('All Stores quick action hidden for cashier',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'user_role': 'cashier'});

    final storeProvider = StoreProvider();

    await tester.pumpWidget(wrapWithDefaultProviders(const HomeScreen(),
        auth: TestAuthCashier(), store: storeProvider));

    await tester.pumpAndSettle();

    // Quick action should not be present for cashier (role-based UI)
    final quickAction = find.widgetWithIcon(IconButton, Icons.store);
    expect(quickAction, findsNothing);
  });

  testWidgets('All Stores quick action visible for admin',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        {'user_role': 'admin', 'access_token': 'fake'});

    final storeProvider = StoreProvider(storeService: FakeStoreServiceForUI());
    // Ensure the provider initializes deterministically for the test
    await storeProvider.loadAvailableStores();
    await storeProvider.loadMyStores();
    await storeProvider.loadStores();

    await tester.pumpWidget(wrapWithDefaultProviders(const HomeScreen(),
        auth: TestAuthAdmin(), store: storeProvider));

    await tester.pumpAndSettle();

    final quickAction = find.widgetWithIcon(IconButton, Icons.store);
    expect(quickAction, findsOneWidget);
    await tester.tap(quickAction);
    await tester.pumpAndSettle();

    // 'All Stores' should be present for admin
    expect(find.text('All Stores'), findsOneWidget);
  });
}
