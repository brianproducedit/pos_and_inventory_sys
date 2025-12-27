import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/cashier_management_screen.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:mobile/widgets/store_switcher_v2.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/user_management_provider.dart';
import 'package:mobile/services/store_service.dart';

class FakeStoreServiceTest extends StoreService {
  @override
  Future<Map<String, dynamic>> getCurrentStore() async {
    return {'current_store': null};
  }

  @override
  Future<List<Map<String, dynamic>>> getStores() async {
    return [
      {'id': 1, 'name': 'Store 1', 'is_active': true},
      {'id': 2, 'name': 'Store 2', 'is_active': true},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getMyStores() async {
    return [
      {'id': 1, 'name': 'Store 1', 'is_active': true},
    ];
  }

  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async {
    return storeId == 0
        ? {'current_store': null}
        : {
            'current_store': {'id': storeId, 'name': 'Store $storeId'}
          };
  }
}

class TestAuthProvider extends AuthProvider {
  final String testRole;
  TestAuthProvider(this.testRole);
  @override
  String? get role => testRole;
}

class FakeUserManagementProvider extends UserManagementProvider {
  @override
  Future<void> loadUsers() async {
    // No-op for widget test to avoid network calls
    return;
  }
}

void main() {
  testWidgets('Cashier app bar shows StoreQuickAction and not StoreSwitcher',
      (tester) async {
    final storeProvider = StoreProvider(storeService: FakeStoreServiceTest());
    final userProvider = FakeUserManagementProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
            value: TestAuthProvider('admin')),
        ChangeNotifierProvider<StoreProvider>.value(value: storeProvider),
        ChangeNotifierProvider<UserManagementProvider>.value(
            value: userProvider),
      ],
      child: MaterialApp(home: CashierManagementScreen()),
    ));

    // Let init/post-frame callbacks run
    await tester.pumpAndSettle();

    // Expect StoreQuickAction to be present in the widget tree and no StoreSwitcher
    expect(find.byType(StoreQuickAction), findsOneWidget);
    expect(find.byType(StoreSwitcher), findsNothing);
  });
}
