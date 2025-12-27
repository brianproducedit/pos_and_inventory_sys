import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/user_management_screen.dart';
import 'package:mobile/providers/user_provider.dart';
import 'package:mobile/providers/auth_provider.dart';

class TestAuth extends AuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  String? get role => 'admin';
}

void main() {
  testWidgets('Invite dialog has labeled fields', (tester) async {
    final userProv = UserProvider();

    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<UserProvider>.value(value: userProv),
      ChangeNotifierProvider<AuthProvider>.value(value: TestAuth()),
    ], child: const MaterialApp(home: UserManagementScreen())));

    await tester.pumpAndSettle();

    // Open invite dialog
    await tester.tap(find.byIcon(Icons.person_add));
    await tester.pumpAndSettle();

    expect(find.text('Invite User'), findsOneWidget);
    // Verify the rendered labels are present (InputDecorator renders them as Text)
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });
}
