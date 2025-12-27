import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/store_management_screen.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/auth_provider.dart';

class TestAuthProvider extends AuthProvider {
  @override
  String? get role => 'superadmin';
}

class TestStoreProvider extends StoreProvider {
  TestStoreProvider() : super();

  final List<int> deleted = [];
  final List<Map<String, dynamic>> _stores = [
    {'id': 1, 'name': 'A', 'location': 'L1', 'is_active': true},
    {'id': 2, 'name': 'B', 'location': 'L2', 'is_active': false},
  ];

  @override
  List<Map<String, dynamic>> get stores => _stores;

  @override
  Future<void> loadStores() async {
    // No-op for tests; we provide static stores via the getter
    notifyListeners();
  }

  @override
  Future<void> deleteStore(int storeId) async {
    deleted.add(storeId);
    _stores.removeWhere((s) => s['id'] == storeId);
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> updateStore(
      int storeId, Map<String, dynamic> storeData) async {
    final idx = _stores.indexWhere((s) => s['id'] == storeId);
    if (idx != -1) {
      _stores[idx] = {..._stores[idx], ...storeData};
    }
    notifyListeners();
    return _stores[idx];
  }
}

void main() {
  testWidgets('Bulk delete and update in StoreManagementScreen',
      (tester) async {
    final prov = TestStoreProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<StoreProvider>.value(value: prov),
        ChangeNotifierProvider<AuthProvider>(create: (_) => TestAuthProvider()),
      ],
      child: const MaterialApp(home: StoreManagementScreen()),
    ));

    await tester.pumpAndSettle();

    // Select both stores
    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsNWidgets(2));

    // Toggle the first checkbox by invoking its onChanged to avoid hit-test flakiness
    final firstCheckbox = tester.widget<Checkbox>(checkboxes.first);
    firstCheckbox.onChanged?.call(true);
    await tester.pumpAndSettle();

    // Bulk bar should appear
    expect(find.text('1 selected'), findsOneWidget);

    // Use Select All to pick all visible stores
    final selectAllIcon = tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.select_all));
    selectAllIcon.onPressed?.call();
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);

    // Clear selection to continue individual toggle flow
    final clearIcon =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.clear));
    clearIcon.onPressed?.call();
    await tester.pumpAndSettle();

    // Re-select the first checkbox
    final firstCheckbox2 = tester.widget<Checkbox>(checkboxes.first);
    firstCheckbox2.onChanged?.call(true);
    await tester.pumpAndSettle();

    // Toggle selected (one active -> expect Deactivate icon)
    final toggleOffIcon = find.byIcon(Icons.toggle_off);
    expect(toggleOffIcon, findsOneWidget);
    final toggleOffBtn =
        find.ancestor(of: toggleOffIcon, matching: find.byType(IconButton));
    final toggleOff = tester.widget<IconButton>(toggleOffBtn);
    toggleOff.onPressed?.call();
    await tester.pumpAndSettle();

    // Confirm dialog appears and accept
    expect(find.text('Confirm'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // The first store should be deactivated
    expect(prov.stores[0]['is_active'], isFalse);

    // After operation the selection is cleared; select both again to perform activate
    final firstCheckbox3 = tester.widget<Checkbox>(checkboxes.first);
    firstCheckbox3.onChanged?.call(true);
    final lastCheckbox3 = tester.widget<Checkbox>(checkboxes.last);
    lastCheckbox3.onChanged?.call(true);
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);

    // Now both are inactive; the toggle should show toggle_on (activate)
    final toggleOnIcon = find.byIcon(Icons.toggle_on);
    expect(toggleOnIcon, findsOneWidget);
    final toggleOnBtn =
        find.ancestor(of: toggleOnIcon, matching: find.byType(IconButton));
    final toggleOn = tester.widget<IconButton>(toggleOnBtn);
    toggleOn.onPressed?.call();
    await tester.pumpAndSettle();

    // Confirm dialog appears and accept
    expect(find.text('Confirm'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // Both stores should now be active
    expect(prov.stores[0]['is_active'], isTrue);
    expect(prov.stores[1]['is_active'], isTrue);

    // Selection is cleared after confirm, select both again to delete
    final firstCheckbox4 = tester.widget<Checkbox>(checkboxes.first);
    firstCheckbox4.onChanged?.call(true);
    final lastCheckbox4 = tester.widget<Checkbox>(checkboxes.last);
    lastCheckbox4.onChanged?.call(true);
    await tester.pumpAndSettle();

    // Delete selected — invoke callback directly to avoid hit-test flakiness in test env
    final deleteIcon = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_forever));
    deleteIcon.onPressed?.call();
    await tester.pumpAndSettle();

    // Confirm dialog appears
    expect(find.text('Delete Stores'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    // Both stores deleted in provider
    expect(prov.deleted, containsAll(<int>[1, 2]));
  });
}
