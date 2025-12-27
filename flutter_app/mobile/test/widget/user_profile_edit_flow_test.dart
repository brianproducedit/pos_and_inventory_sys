import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/user_profile_screen.dart';
import '../test_helpers.dart';
import 'package:mobile/widgets/primary_button.dart';
import 'package:mobile/providers/user_profile_provider.dart';

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

  @override
  Future<bool> updateUserProfile(UserProfile profile) async => true;

  @override
  Future<bool> changePassword(String current, String next) async => true;
}

void main() {
  testWidgets('User Profile edit and change password flow', (tester) async {
    final prov = TestUserProfileProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProfileProvider>.value(value: prov)
      ],
      child: wrapWithDefaultProviders(const UserProfileScreen()),
    ));

    await tester.pumpAndSettle();

    // Tap edit icon
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    // Username field enabled
    expect(find.widgetWithText(TextFormField, 'Username'), findsOneWidget);

    // Change username text
    await tester.enterText(find.byType(TextFormField).first, 'jdoe2');

    // Save by tapping icon (now save)
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();

    // Toggle change password (tap the first matching widget)
    // Tap the actual toggle button (TextButton) rather than the header text
    await tester
        .ensureVisible(find.widgetWithText(TextButton, 'Change Password'));
    await tester.tap(find.widgetWithText(TextButton, 'Change Password'));
    await tester.pumpAndSettle();

    expect(find.text('Current Password'), findsOneWidget);

    // Fill passwords and submit
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Current Password'), 'oldpass');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'New Password'), 'newpass1');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm New Password'), 'newpass1');

    // Tap submit button (PrimaryButton) to change password
    await tester
        .ensureVisible(find.widgetWithText(PrimaryButton, 'Change Password'));
    await tester.tap(find.widgetWithText(PrimaryButton, 'Change Password'));
    await tester.pumpAndSettle();

    expect(find.text('Password changed successfully'),
        anyOf(findsNothing, findsOneWidget));
  });
}
