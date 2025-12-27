import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/inventory_provider.dart';
import '../test_helpers.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/user_management_screen.dart';
import 'package:mobile/providers/user_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/widgets/primary_button.dart';

class TestUserProvider extends UserProvider {
  // Maintain a local list since base class private fields aren't accessible here
  final List<Map<String, dynamic>> _localUsers = [
    {'id': 1, 'name': 'Alice', 'email': 'alice@example.com'},
  ];

  @override
  List<Map<String, dynamic>> get users =>
      List<Map<String, dynamic>>.from(_localUsers);

  @override
  Future<void> updateUser(int id, Map<String, dynamic> userData) async {
    final idx = _localUsers.indexWhere((u) => u['id'] == id);
    if (idx != -1) {
      _localUsers[idx] = {..._localUsers[idx], ...userData};
      notifyListeners();
    }
  }
}

class TestAuth extends AuthProvider {
  @override
  String? get role => 'admin';
}

void main() {
  testWidgets('Edit User dialog validation and update', (tester) async {
    final prov = TestUserProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: prov),
      ],
      child: wrapWithDefaultProviders(const UserManagementScreen(),
          auth: TestAuth(), inventory: InventoryProvider()),
    ));

    await tester.pumpAndSettle();

    // Tap edit icon
    expect(find.byIcon(Icons.edit), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pumpAndSettle();

    expect(find.text('Edit User'), findsOneWidget);

    // Clear name to trigger validation - use TextFormField by index
    final nameField = find.byType(TextFormField).at(0);
    final emailField = find.byType(TextFormField).at(1);

    await tester.enterText(nameField, '');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Update'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a name'), findsOneWidget);

    // Enter invalid email
    await tester.enterText(nameField, 'Alice A');
    await tester.enterText(emailField, 'invalid');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Update'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid email'), findsOneWidget);

    // Enter valid values and update
    await tester.enterText(emailField, 'alice@updated.com');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Update'));
    await tester.pumpAndSettle();

    expect(find.text('Alice A'), findsOneWidget);
    expect(find.text('alice@updated.com'), findsOneWidget);
  });
}
