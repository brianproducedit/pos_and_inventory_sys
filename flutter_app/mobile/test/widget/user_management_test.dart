import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/user_management_screen.dart';
import '../test_helpers.dart';
import 'package:mobile/providers/user_provider.dart';
import 'package:mobile/providers/auth_provider.dart';

class TestUserProvider extends UserProvider {
  @override
  List<Map<String, dynamic>> get users => [
        {'id': 1, 'name': 'Alice', 'email': 'alice@example.com'},
        {'id': 2, 'name': 'Bob', 'email': 'bob@example.com'},
      ];
}

class TestAuth extends AuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  String? get role => 'admin';
}

void main() {
  testWidgets('User Management shows users and invite button', (tester) async {
    final userProv = TestUserProvider();
    final auth = TestAuth();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: userProv),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: wrapWithDefaultProviders(const UserManagementScreen()),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byIcon(Icons.person_add), findsOneWidget);
  });
}
