import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/pos_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/services/product_service.dart';
import 'package:mobile/services/store_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeProductService extends ProductService {
  int callCount = 0;

  @override
  Future<List<Map<String, dynamic>>> getProducts({int? storeId}) async {
    callCount++;
    return [
      {'id': 1, 'name': 'P1', 'price': 10.0, 'stock_quantity': 5}
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

  test('PosProvider reloads products when store changes', () async {
    final fakeProd = FakeProductService();
    final pos = PosProvider(productService: fakeProd);
    final storeProvider = StoreProvider(storeService: FakeStoreService());

    pos.setStoreProvider(storeProvider);

    // simulate switching to store 2
    await storeProvider.switchStore({'id': 2});

    // wait for debounce and async load
    await Future.delayed(const Duration(milliseconds: 300));

    expect(fakeProd.callCount, greaterThanOrEqualTo(1));
  });
}
