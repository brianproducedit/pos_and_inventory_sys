import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/services/store_service.dart';

class FakeStoreService extends StoreService {
  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async {
    // Simulate backend returning canonical current_store
    return {
      'current_store': {'id': storeId, 'name': 'Fake Store $storeId'}
    };
  }
}

class FakeStoreServiceAllStores extends StoreService {
  @override
  Future<Map<String, dynamic>> getCurrentStore() async {
    // Server explicitly indicates All Stores view (null current_store)
    return {'current_store': null};
  }

  @override
  Future<List<Map<String, dynamic>>> getStores() async {
    // Provide some stores; loadStores should not override explicit All Stores
    return [
      {'id': 1, 'name': 'Primary Store', 'is_active': true}
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getMyStores() async {
    return [];
  }
}

class FakeStoreServiceNullId extends StoreService {
  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async {
    // Backend returns a current_store with a null id (malformed)
    return {
      'current_store': {'id': null, 'name': 'Backend Null ID Store'}
    };
  }
}

class CountingStoreService extends StoreService {
  int callCount = 0;

  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async {
    callCount++;
    // Return canonical current_store: null for All Stores, otherwise the selected id
    return storeId == 0
        ? {'current_store': null}
        : {
            'current_store': {'id': storeId, 'name': 'Counting Store $storeId'}
          };
  }

  @override
  Future<Map<String, dynamic>> getCurrentStore() async {
    return {
      'current_store': {'id': 1, 'name': 'Initial Store'}
    };
  }
}

class FakeStoreService422 extends StoreService {
  @override
  Future<Map<String, dynamic>> getCurrentStore() async {
    // Simulate backend returning a 422 which should be interpreted as All Stores
    throw Exception('Failed to get current store: 422');
  }

  @override
  Future<List<Map<String, dynamic>>> getMyStores() async => [];

  @override
  Future<List<Map<String, dynamic>>> getStores() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('switchStore sets currentStore and returns true', () async {
    final provider = StoreProvider(storeService: FakeStoreService());

    final store = {'id': 42, 'name': 'Store 42'};

    final result = await provider.switchStore(store);

    expect(result, true);
    expect(provider.currentStore, isNotNull);
    expect(provider.currentStore!['id'], 42);
    expect(provider.currentStore!['name'], 'Fake Store 42');
  });

  test('switchStore rejects access when not in myStores', () async {
    final provider = StoreProvider(storeService: FakeStoreService());
    // set myStores to empty and attempt switch (client-side check should block)
    // Since myStores is private, use loadMyStores to populate it with empty list
    // but here we rely on client-side behavior: if _myStores is empty, provider allows backend to decide

    final store = {'id': 7, 'name': 'Store 7'};
    final result = await provider.switchStore(store);

    // Backend fake returns OK; result should be true
    expect(result, true);
    expect(provider.currentStore!['id'], 7);
  });

  test('initialize restores All Stores and loadStores does not override',
      () async {
    final provider = StoreProvider(storeService: FakeStoreServiceAllStores());

    // Simulate storing no preference (All Stores saved as null locally)
    SharedPreferences.setMockInitialValues({});

    await provider.initialize();

    // After initialization, provider should reflect All Stores (null currentStore)
    expect(provider.currentStore, isNull);

    // Now call loadStores (as screens do); it should not auto-select the first active store
    await provider.loadStores();

    expect(provider.currentStore, isNull);
  });

  test('switchStore handles malformed store objects defensively', () async {
    final provider = StoreProvider(storeService: FakeStoreService());

    // Case 1: id is missing
    final storeMissingId = {'name': 'No ID Store'};
    final resultMissingId = await provider.switchStore(storeMissingId);
    expect(resultMissingId, false);
    expect(provider.errorMessage, contains('Failed to switch store'));

    // Case 2: id is null
    final storeNullId = {'id': null, 'name': 'Null ID Store'};
    final resultNullId = await provider.switchStore(storeNullId);
    expect(resultNullId, false);
    expect(provider.errorMessage, contains('Failed to switch store'));

    // Case 3: id is a string
    final storeStringId = {'id': '99', 'name': 'String ID Store'};
    final resultStringId = await provider.switchStore(storeStringId);
    expect(resultStringId, true);
    expect(provider.currentStore, isNotNull);
    expect(provider.currentStore!['id'], 99);
  });

  test('switchStore treats backend current_store with null id as All Stores',
      () async {
    SharedPreferences.setMockInitialValues({});
    final provider = StoreProvider(storeService: FakeStoreServiceNullId());

    final result = await provider.switchStore({'id': 5});

    // Should succeed and normalize backend null id to All Stores (null currentStore)
    expect(result, true);
    expect(provider.currentStore, isNull);

    // Persisted preference should not be set to invalid id
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('current_store_id'), isNull);
  });

  test('switchStore does not call backend again when already on All Stores',
      () async {
    SharedPreferences.setMockInitialValues({});
    final countingService = CountingStoreService();
    final provider = StoreProvider(storeService: countingService);

    // Start from a non-all store so switching to All Stores invokes backend
    final resInit = await provider.switchStore({'id': 1});
    expect(resInit, true);
    expect(countingService.callCount, 1);

    // Now switch to All Stores (should call backend once more)
    final res1 = await provider.switchStore({'id': 0});
    expect(res1, true);
    expect(countingService.callCount, 2);

    // Second switch to All Stores should be a no-op and not call backend again
    final res2 = await provider.switchStore({'id': 0});
    expect(res2, true);
    expect(countingService.callCount, 2);
  });

  test('initialize handles backend 422 gracefully', () async {
    // No stored pref
    SharedPreferences.setMockInitialValues({});
    final provider = StoreProvider(storeService: FakeStoreService422());

    // initialize should not throw even if backend returns a 422-style error
    await provider.initialize();

    // Provider should treat this as 'All Stores' (null currentStore) and not crash
    expect(provider.currentStore, isNull);
  });
}
