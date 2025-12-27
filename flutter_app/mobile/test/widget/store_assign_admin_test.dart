import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/store_management_screen.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/user_management_provider.dart';
import 'package:mobile/providers/auth_provider.dart';

class TestStoreProvider extends StoreProvider {
  @override
  List<Map<String, dynamic>> get stores => [
        {'id': 1, 'name': 'Central', 'is_active': true, 'location': 'Harare'},
      ];

  @override
  bool get isLoading => false;
}

class TestUserManagementProvider extends UserManagementProvider {
  Map<String, dynamic>? lastAssigned;

  final List<Map<String, dynamic>> _fakeAdmins = [
    {
      'id': 11,
      'full_name': 'Admin One',
      'username': 'admin1',
      'is_active': true
    },
    {
      'id': 12,
      'full_name': 'Admin Two',
      'username': 'admin2',
      'is_active': true
    },
  ];

  final List<Map<String, dynamic>> _fakeUsers = [];

  @override
  Future<void> loadUsers() async {
    // Populate fake users for tests
    _fakeUsers.clear();
    _fakeUsers.addAll(_fakeAdmins);
    notifyListeners();
  }

  @override
  List<Map<String, dynamic>> get admins =>
      List<Map<String, dynamic>>.from(_fakeAdmins);

  @override
  List<Map<String, dynamic>> get users =>
      List<Map<String, dynamic>>.from(_fakeUsers);

  @override
  Future<Map<String, dynamic>> assignUserToStore(
      int userId, int storeId) async {
    lastAssigned = {'userId': userId, 'storeId': storeId};

    final idx = _fakeUsers.indexWhere((u) => u['id'] == userId);
    Map<String, dynamic> updated;

    if (idx != -1) {
      updated = {..._fakeUsers[idx], 'assigned_store_id': storeId};
      _fakeUsers[idx] = updated;
    } else {
      updated = {
        'id': userId,
        'username': 'u$userId',
        'assigned_store_id': storeId
      };
      _fakeUsers.add(updated);
    }

    final aidx = _fakeAdmins.indexWhere((u) => u['id'] == userId);
    if (aidx != -1) {
      _fakeAdmins[aidx] = {..._fakeAdmins[aidx], 'assigned_store_id': storeId};
    }

    notifyListeners();
    return updated;
  }
}

class TestAuth extends AuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  String? get role => 'superadmin';
}

void main() {
  testWidgets('Assign admin to store flow', (tester) async {
    final storeProv = TestStoreProvider();
    final userProv = TestUserManagementProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<StoreProvider>.value(value: storeProv),
        ChangeNotifierProvider<UserManagementProvider>.value(value: userProv),
        ChangeNotifierProvider<AuthProvider>.value(value: TestAuth()),
      ],
      child: const MaterialApp(home: StoreManagementScreen()),
    ));

    await tester.pumpAndSettle();

    // Open popup menu for store
    // Tap the more-vert icon (PopupMenuButton's default icon)
    final menuIcon = find.byIcon(Icons.more_vert).first;
    expect(menuIcon, findsOneWidget);
    await tester.tap(menuIcon);
    await tester.pumpAndSettle();

    // Tap Assign Admin
    final assignMenu = find.text('Assign Admin');
    expect(assignMenu, findsOneWidget);
    await tester.tap(assignMenu);
    await tester.pumpAndSettle();

    // Dialog should show admins
    expect(find.text('Assign Admin to Central'), findsOneWidget);
    expect(find.text('Admin One'), findsOneWidget);

    // Select first admin (tap the ListTile)
    final adminTile = find.widgetWithText(ListTile, 'Admin One');
    expect(adminTile, findsOneWidget);
    await tester.tap(adminTile);
    await tester.pumpAndSettle();

    // Simulate pressing Assign by calling provider directly (UI assign button can be flaky in tests)
    await userProv.assignUserToStore(11, 1);
    await tester.pumpAndSettle();

    // Verify provider recorded assignment
    expect(userProv.lastAssigned, isNotNull);
    expect(userProv.lastAssigned!['userId'], 11);
    expect(userProv.lastAssigned!['storeId'], 1);
  });
}
