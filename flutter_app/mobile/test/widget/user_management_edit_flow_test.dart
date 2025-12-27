import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/primary_button.dart';
import 'package:mobile/widgets/primary_text_field.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/user_management_screen.dart';
import '../test_helpers.dart';
import 'package:mobile/providers/user_provider.dart';
import 'package:mobile/providers/auth_provider.dart';

class TestAuth extends AuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  String? get role => 'admin';
}

void main() {
  testWidgets('Invite, edit, and delete user flow', (tester) async {
    final userProv = UserProvider();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: userProv),
        ChangeNotifierProvider<AuthProvider>.value(value: TestAuth()),
      ],
      child: wrapWithDefaultProviders(const UserManagementScreen()),
    ));

    await tester.pumpAndSettle();

    // Initially empty
    expect(find.text('No users yet'), findsOneWidget);

    // Open invite dialog (tap FAB)
    await tester.tap(find.byIcon(Icons.person_add));
    await tester.pumpAndSettle();

    // Try invalid submit (dialog's Invite button)
    await tester.tap(find.widgetWithText(PrimaryButton, 'Invite'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a name'), findsOneWidget);

    // Enter details
    await tester.enterText(
        find.widgetWithText(PrimaryTextField, 'Name'), 'Charlie');
    await tester.enterText(
        find.widgetWithText(PrimaryTextField, 'Email'), 'charlie@example.com');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Invite'));
    await tester.pumpAndSettle();

    expect(find.text('Charlie'), findsOneWidget);

    // Edit the user
    await tester.tap(find.widgetWithIcon(IconButton, Icons.edit).first);
    await tester.pumpAndSettle();

    expect(find.text('Edit User'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'), 'Charlie X');
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.text('Charlie X'), findsOneWidget);

    // Delete the user
    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Are you sure'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Charlie X'), findsNothing);
  });
}
