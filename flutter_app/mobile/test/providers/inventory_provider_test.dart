import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/inventory_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/services/product_service.dart';
import 'package:mobile/services/store_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeProductService extends ProductService {
  int callCount = 0;

  @override
  Future<List<Map<String, dynamic>>> getLowStockAlerts({int? storeId}) async {
    callCount++;
    return [
      {'id': 1, 'name': 'P1', 'stock_quantity': 4, 'alert_level': 'Critical'},
      {'id': 2, 'name': 'P2', 'stock_quantity': 7, 'alert_level': 'Low'}
    ];
  }
}

class FakeStoreService extends StoreService {
  Map<String, dynamic>? _current;

  @override
  Future<Map<String, dynamic>> getCurrentStore() async {
    return {'current_store': _current};
  }

  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async {
    _current = {'id': storeId, 'name': 'Store $storeId'};
    return {'current_store': _current};
  }

  @override
  Future<List<Map<String, dynamic>>> getMyStores() async => [];
  @override
  Future<List<Map<String, dynamic>>> getStores() async => [];
}

class FakeProductServiceWithAll extends ProductService {
  int getProductsCallCount = 0;
  int getAllCallCount = 0;
  final List<Map<String, dynamic>> allProducts = [
    {'id': 1, 'name': 'A'},
    {'id': 2, 'name': 'B'}
  ];

  @override
  Future<List<Map<String, dynamic>>> getProducts({int? storeId}) async {
    getProductsCallCount++;
    return [
      {'id': 1, 'name': 'A', 'store_id': storeId}
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getAllProducts(
      {bool includeInactive = false, int? storeId}) async {
    getAllCallCount++;
    return allProducts;
  }
}

class FakeAuthProviderForInventory extends AuthProvider {
  final String _role;
  FakeAuthProviderForInventory(this._role);

  @override
  bool get isAuthenticated => true;
  @override
  String? get role => _role;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('loadLowStockAlerts updates alerts and counts', () async {
    final fake = FakeProductService();
    final inventory = InventoryProvider(productService: fake);

    expect(inventory.lowStockAlerts, isEmpty);
    await inventory.loadLowStockAlerts();

    expect(fake.callCount, 1);
    expect(inventory.lowStockAlerts.length, 2);
    expect(inventory.lowStockCount, 2);
    expect(inventory.criticalLowStockCount, 1);
  });

  test('InventoryProvider reloads alerts when store changes', () async {
    final fake = FakeProductService();
    final inventory = InventoryProvider(productService: fake);
    final storeProvider = StoreProvider(storeService: FakeStoreService());

    inventory.setStoreProvider(storeProvider);

    // simulate switching to store 2
    await storeProvider.switchStore({'id': 2});

    // wait for unawaited async call to complete
    await Future.delayed(const Duration(milliseconds: 200));

    expect(fake.callCount, greaterThanOrEqualTo(1));
  });

  test('admin with All Stores selected calls getAllProducts', () async {
    final fake = FakeProductServiceWithAll();
    final inventory = InventoryProvider(productService: fake);
    final auth = FakeAuthProviderForInventory('admin');

    inventory.setAuthProvider(auth);
    inventory.setCurrentStoreForTest({'id': 0});

    await inventory.loadProducts();

    expect(fake.getAllCallCount, 1);
    expect(fake.getProductsCallCount, 0);
    expect(inventory.products, equals(fake.allProducts));
  });
}
