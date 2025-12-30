import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../test_helpers.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/services/store_service.dart';

class _FakeCreateAssignService extends StoreService {
  bool assigned = false;

  @override
  Future<Map<String, dynamic>> createStore(
      Map<String, dynamic> storeData) async {
    // Simulate backend assigning id 77
    return {'id': 77, 'name': storeData['name'] ?? 'New Store'};
  }

  @override
  Future<void> assignAdminToStore(int storeId, int adminId) async {
    if (storeId == 77 && adminId == 7) {
      assigned = true;
      return;
    }
    throw Exception('Failed to assign');
  }

  @override
  Future<List<Map<String, dynamic>>> getStoreUsers(int storeId) async {
    if (storeId == 77)
      return [
        {'id': 7, 'username': 'admin7'}
      ];
    return [];
  }

  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async {
    if (storeId == 77)
      return {
        'current_store': {'id': 77, 'name': 'New Store'}
      };
    return {
      'current_store': {'id': storeId}
    };
  }
}

void main() {
  setUp(() async {
    initializeTestHelpersOnce();
  });

  testWidgets('Superadmin can create a store and assign an admin',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'access_token': 'super-token', 'user_role': 'superadmin'});

    final svc = _FakeCreateAssignService();
    final provider = StoreProvider(storeService: svc);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<StoreProvider>.value(value: provider),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ElevatedButton(
                key: const Key('create-store-77'),
                onPressed: () async {
                  await provider.createStore({'name': 'New Store'});
                },
                child: const Text('Create Store 77'),
              ),
              ElevatedButton(
                key: const Key('switch-to-77'),
                onPressed: () async {
                  await provider.switchStore({'id': 77});
                },
                child: const Text('Switch to 77'),
              ),
              ElevatedButton(
                key: const Key('assign-admin-7'),
                onPressed: () async {
                  await provider.assignAdminToStore(77, 7);
                },
                child: const Text('Assign Admin 7'),
              ),
              Builder(builder: (context) {
                final prov = Provider.of<StoreProvider>(context);
                final stores = prov.stores.map((s) => s['id']).join(',');
                final users = prov.storeUsers.map((u) => u['id']).join(',');
                return Column(
                  children: [
                    Text('Stores: $stores', key: const Key('storesList')),
                    Text('Users: $users', key: const Key('usersList')),
                    Text(prov.errorMessage ?? '', key: const Key('errorText')),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    // Create store
    await tester.tap(find.byKey(const Key('create-store-77')));
    await tester.pumpAndSettle();
    expect(provider.stores.any((s) => s['id'] == 77), isTrue);
    expect(find.byKey(const Key('storesList')), findsOneWidget);
    expect(find.text('Stores: 77'), findsOneWidget);

    // Switch to it
    await tester.tap(find.byKey(const Key('switch-to-77')));
    await tester.pumpAndSettle();

    // Assign admin
    await tester.tap(find.byKey(const Key('assign-admin-7')));
    await tester.pumpAndSettle();

    expect(svc.assigned, isTrue);

    // After assignment, storeUsers should reflect the assigned user
    expect(provider.storeUsers.any((u) => u['id'] == 7), isTrue);
    expect(find.byKey(const Key('usersList')), findsOneWidget);
    expect(find.text('Users: 7'), findsOneWidget);
  });
}
