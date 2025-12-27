import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/cashier_management_screen.dart';
import 'package:mobile/providers/user_management_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/auth_provider.dart';

class TestUserManagementProvider extends UserManagementProvider {
  @override
  bool get isLoading => false;

  @override
  List<Map<String, dynamic>> get cashiers => [];
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
  String? get role => 'admin';
}

void main() {
  testWidgets('Create Cashier dialog shows PrimaryTextField fields',
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
      child: const MaterialApp(home: CashierManagementScreen()),
    ));

    await tester.pumpAndSettle();

    // Tap the add button in the AppBar
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Create New Cashier'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Full Name'), findsOneWidget);
  });
}
