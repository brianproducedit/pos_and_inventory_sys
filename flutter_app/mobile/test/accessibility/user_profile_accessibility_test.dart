import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/inventory_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/user_profile_screen.dart';
import 'package:mobile/providers/user_profile_provider.dart';
import '../test_helpers.dart';

class TestAuth extends AuthProvider {
  @override
  bool get isAuthenticated => true;

  @override
  String? get role => 'admin';
}

class TestUserProfileProvider extends UserProfileProvider {
  TestUserProfileProvider() : super(authProvider: TestAuth());

  @override
  bool get isLoading => false;

  @override
  UserProfile? get userProfile => UserProfile(
        id: 1,
        username: 'jdoe',
        fullName: 'John Doe',
        role: 'admin',
        isActive: true,
        storeId: null,
        createdAt: DateTime.utc(2025, 1, 1),
        updatedAt: DateTime.utc(2025, 1, 1),
      );

  @override
  Future<void> loadUserProfile() async {}
}

void main() {
  testWidgets('User profile accessible and shows fields', (tester) async {
    await initTestEnvironment();
    final prov = TestUserProfileProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: TestAuth()),
        ChangeNotifierProvider<UserProfileProvider>.value(value: prov),
        ChangeNotifierProvider<StoreProvider>.value(value: TestStoreProvider()),
        ChangeNotifierProvider<InventoryProvider>.value(
            value: TestInventoryProvider()),
        ChangeNotifierProvider<AnalyticsProvider>.value(
            value: TestAnalyticsProvider()),
      ],
      child: const MaterialApp(home: UserProfileScreen()),
    ));

    await tester.pumpAndSettle();

    expect(find.text('User Profile'), findsOneWidget);
    expect(find.text('Profile Information'), findsOneWidget);
    // Accept multiple matches for Change Password (may appear in header and button)
    expect(find.text('Change Password'), findsWidgets);
  });
}
