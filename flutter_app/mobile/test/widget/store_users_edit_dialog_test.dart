import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/store_users_screen.dart';
import '../test_helpers.dart';
import 'package:mobile/providers/user_management_provider.dart';

class TestUserManagementProvider extends UserManagementProvider {
  @override
  Future<List<Map<String, dynamic>>> getUsersByStore(int? storeId) async {
    return [
      {
        'id': 1,
        'username': 'till1',
        'full_name': 'Till One',
        'is_active': true,
        'role': 'cashier'
      }
    ];
  }

  @override
  Future<Map<String, dynamic>> updateUser(
      int id, Map<String, dynamic> userData) async {
    // Simulate an update and return the updated user record for tests
    return <String, dynamic>{'id': id, ...userData};
  }
}

class TestAuth extends AuthProvider {
  @override
  String? get role => 'superadmin';
}

void main() {
  testWidgets('Store Users edit dialog validation', (tester) async {
    final prov = TestUserManagementProvider();
    final store = {'id': 1, 'name': 'Central'};

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserManagementProvider>.value(value: prov),
        ChangeNotifierProvider<AuthProvider>.value(value: TestAuth()),
      ],
      child: wrapWithDefaultProviders(StoreUsersScreen(store: store),
          store: StoreProvider()),
    ));

    await tester.pumpAndSettle();

    // Open popup menu
    await tester.tap(find.widgetWithIcon(IconButton, Icons.more_vert).first);
    await tester.pumpAndSettle();

    // Tap edit
    await tester.tap(find.text('Edit User'));
    await tester.pumpAndSettle();

    expect(find.text('Edit User'), findsOneWidget);

    // Clear the name and try update
    await tester.enterText(find.widgetWithText(TextFormField, 'Full Name'), '');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Update'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter full name'), findsOneWidget);
  });
}
