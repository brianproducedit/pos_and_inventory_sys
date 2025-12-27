import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/admin_management_screen.dart';
import 'package:mobile/providers/user_management_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/auth_provider.dart';

class TestUserManagementProvider extends UserManagementProvider {
  @override
  bool get isLoading => false;

  @override
  List<Map<String, dynamic>> get admins => [];
}

class TestStoreProvider extends StoreProvider {
  @override
  bool get isLoading => false;

  @override
  List<Map<String, dynamic>> get stores => [
        {'id': 1, 'name': 'Central'},
      ];
}

class TestAuth extends AuthProvider {
  @override
  bool get isAuthenticated => true;

  @override
  String? get role => 'superadmin';
}

void main() {
  testWidgets('Create Admin dialog shows PrimaryTextField fields',
      (tester) async {
    final userProv = TestUserManagementProvider();
    final storeProv = TestStoreProvider();
    final auth = TestAuth();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserManagementProvider>.value(value: userProv),
        ChangeNotifierProvider<StoreProvider>.value(value: storeProv),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: const MaterialApp(home: AdminManagementScreen()),
    ));

    await tester.pumpAndSettle();

    // Tap the add button in the AppBar
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Create New Admin'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Full Name'), findsOneWidget);
  });
}
