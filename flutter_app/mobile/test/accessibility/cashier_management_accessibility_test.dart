import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/cashier_management_screen.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/user_management_provider.dart';
import 'package:mobile/providers/store_provider.dart';

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
  List<Map<String, dynamic>> get stores => [];
}

class TestAuth extends AuthProvider {
  @override
  bool get isAuthenticated => true;

  @override
  String? get role => 'admin';
}

void main() {
  testWidgets('Cashier Management accessible and shows header', (tester) async {
    final userProv = TestUserManagementProvider();
    final auth = TestAuth();

    final storeProv = TestStoreProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserManagementProvider>.value(value: userProv),
        ChangeNotifierProvider<StoreProvider>.value(value: storeProv),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: const MaterialApp(home: CashierManagementScreen()),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Cashier Management'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
