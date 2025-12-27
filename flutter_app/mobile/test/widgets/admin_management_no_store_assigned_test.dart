import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/admin_management_screen.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/user_management_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/analytics_provider.dart';

class FakeAuthProvider extends AuthProvider {
  @override
  String get role => 'superadmin';

  @override
  Future<void> checkAuthStatus() async {}

  @override
  Future<String?> getToken() async => null;

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> logout() async {}
}

class FakeUserManagementProvider extends UserManagementProvider {
  List<Map<String, dynamic>> _fakeAdmins = [
    {
      'id': 1,
      'username': 'admin1',
      'full_name': 'Admin One',
      'store_id': 0,
      'is_active': true,
      'role': 'admin',
    }
  ];

  @override
  List<Map<String, dynamic>> get admins => _fakeAdmins;

  @override
  List<Map<String, dynamic>> get users => _fakeAdmins;

  @override
  Future<void> loadUsers() async {
    // no-op; data is provided via getters
    return;
  }
}

class FakeStoreProvider extends StoreProvider {
  @override
  Future<void> loadStores() async {
    // no-op; keep stores empty
    return;
  }

  @override
  List<Map<String, dynamic>> get stores => [];

  @override
  bool get isLoading => false;

  @override
  Map<String, dynamic>? get currentStore => null;
}

class _TestAnalyticsProvider extends AnalyticsProvider {
  @override
  Future<void> loadAnalytics({int? storeId}) async {}
}

void main() {
  testWidgets(
      'Admin screen shows "No Store Assigned" for admins with store_id 0',
      (WidgetTester tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuthProvider()),
        ChangeNotifierProvider<UserManagementProvider>(
            create: (_) => FakeUserManagementProvider()),
        ChangeNotifierProvider<StoreProvider>(
            create: (_) => FakeStoreProvider()),
        // AnalyticsProvider is required by StoreSwitcher; provide a minimal fake
        ChangeNotifierProvider<AnalyticsProvider>(
            create: (_) => _TestAnalyticsProvider()),
      ],
      child: MaterialApp(home: AdminManagementScreen()),
    ));

    // Allow initState async calls to settle
    await tester.pumpAndSettle();

    expect(find.text('No Store Assigned'), findsOneWidget);
  });
}
