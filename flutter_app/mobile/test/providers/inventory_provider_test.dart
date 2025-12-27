import 'package:flutter_test/flutter_test.dart';
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
}
