import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/store_management_screen.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/auth_provider.dart';

class TestStoreProvider extends StoreProvider {
  @override
  List<Map<String, dynamic>> get stores => [
        {'id': 1, 'name': 'Central', 'is_active': true, 'location': 'Harare'},
        {'id': 2, 'name': 'Branch', 'is_active': false, 'location': 'Bulawayo'},
      ];

  @override
  bool get isLoading => false;
}

class TestAuth extends AuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  String? get role => 'superadmin';
}

void main() {
  testWidgets('Store Management accessible and shows stores', (tester) async {
    final stores = TestStoreProvider();
    final auth = TestAuth();

    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<StoreProvider>.value(value: stores),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
    ], child: const MaterialApp(home: StoreManagementScreen())));

    await tester.pumpAndSettle();

    expect(find.text('Store Management'), findsOneWidget);
    expect(find.text('Central'), findsOneWidget);
    expect(find.text('Branch'), findsOneWidget);
  });
}
