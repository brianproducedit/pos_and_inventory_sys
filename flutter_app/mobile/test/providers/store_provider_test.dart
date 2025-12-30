import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/services/store_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStoreService extends StoreService {
  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async {
    if (storeId == 0) return {'current_store': null};
    return {
      'current_store': {'id': storeId}
    };
  }
}

class _ForbiddenStoreService extends StoreService {
  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async {
    throw Exception('Failed to switch store: 403');
  }
}

class _CreateAssignStoreService extends StoreService {
  bool assigned = false;

  @override
  Future<Map<String, dynamic>> createStore(
      Map<String, dynamic> storeData) async {
    return {'id': 99, 'name': storeData['name'] ?? 'New Store'};
  }

  @override
  Future<void> assignAdminToStore(int storeId, int adminId) async {
    if (storeId == 99 && adminId == 7) {
      assigned = true;
      return;
    }
    throw Exception('Failed to assign');
  }

  @override
  Future<List<Map<String, dynamic>>> getStoreUsers(int storeId) async {
    if (storeId == 99)
      return [
        {'id': 7, 'username': 'admin7'}
      ];
    return [];
  }

  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async {
    if (storeId == 99)
      return {
        'current_store': {'id': 99, 'name': 'New Store'}
      };
    return {
      'current_store': {'id': storeId}
    };
  }
}

class _NullCurrentStoreService extends StoreService {
  @override
  Future<Map<String, dynamic>> getCurrentStore() async {
    return {'current_store': null};
  }

  @override
  Future<List<Map<String, dynamic>>> getMyStores() async {
    return [
      {'id': 1, 'name': 'Store 1', 'is_active': true}
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('non-admin cannot switch to All Stores', () async {
    SharedPreferences.setMockInitialValues({'user_role': 'cashier'});
    final provider = StoreProvider(storeService: _FakeStoreService());

    final success = await provider.switchStore({'id': 0});
    expect(success, isFalse);
    expect(provider.errorMessage, contains('insufficient permissions'));
  });

  test('admin can switch to All Stores', () async {
    SharedPreferences.setMockInitialValues({'user_role': 'admin'});
    final provider = StoreProvider(storeService: _FakeStoreService());

    final success = await provider.switchStore({'id': 0});
    expect(success, isTrue);
    expect(provider.currentStore, isNull);
  });

  test('admin cannot switch to other admin\'s store when backend denies',
      () async {
    SharedPreferences.setMockInitialValues({'user_role': 'admin'});

    // Use top-level _ForbiddenStoreService which simulates a 403 from backend on switch
    final provider = StoreProvider(storeService: _ForbiddenStoreService());

    final success = await provider.switchStore({'id': 2});
    expect(success, isFalse);
    expect(provider.errorMessage, contains('Failed to switch store'));
  });

  test('superadmin can create a store and assign an admin', () async {
    SharedPreferences.setMockInitialValues({'user_role': 'superadmin'});

    final svc = _CreateAssignStoreService();
    final provider = StoreProvider(storeService: svc);

    final newStore = await provider.createStore({'name': 'New Store'});
    expect(newStore['id'], 99);
    expect(provider.stores.any((s) => s['id'] == 99), isTrue);

    // Switch to the newly created store (simulate backend switch success)
    final switched = await provider.switchStore({'id': 99});
    expect(switched, isTrue);

    await provider.assignAdminToStore(99, 7);
    expect(svc.assigned, isTrue);
    expect(provider.storeUsers.any((u) => u['id'] == 7), isTrue);
  });

  test('initialize prevents non-admin being restored to All Stores', () async {
    // Simulate backend returning current_store=null but role is cashier; expect fallback to myStores
    SharedPreferences.setMockInitialValues({'user_role': 'cashier'});

    final provider = StoreProvider(storeService: _NullCurrentStoreService());

    await provider.initialize();
    // allow background init to complete
    await Future.delayed(const Duration(milliseconds: 50));

    // Expect provider.currentStore to be the first myStore (fallback)
    expect(provider.currentStore, isNotNull);
    expect(provider.currentStore!['id'], 1);
  });
}
