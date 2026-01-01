import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/pos_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/services/product_service.dart';
import 'package:mobile/services/store_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/services/sales_service.dart';
import 'package:mobile/domain/models/product.dart';
import 'package:mobile/data/repositories/product_repository.dart';
import 'package:mobile/data/local/database_helper.dart';

class FakeProductService extends ProductService {
  int callCount = 0;
  int? lastStoreId;

  @override
  Future<List<Map<String, dynamic>>> getProducts({int? storeId}) async {
    callCount++;
    lastStoreId = storeId;
    return [
      {'id': 1, 'name': 'P1', 'price': 10.0, 'stock_quantity': 5}
    ];
  }
}

class FakeProductRepository extends ProductRepository {
  final List<_FakeProduct> _items;
  FakeProductRepository(this._items) : super(db: DatabaseHelper());

  @override
  Future<List<Product>> getAllProducts({int? storeId}) async {
    final filteredItems = storeId != null
        ? _items.where((item) => item.storeId == storeId).toList()
        : _items;
    return filteredItems.map((i) => Product.fromMap(i.toMap())).toList();
  }
}

class _FakeProduct {
  final int id;
  final int storeId;
  final int stockQuantity;
  final int? serverId;
  _FakeProduct(
      {required this.id,
      required this.storeId,
      this.stockQuantity = 5,
      this.serverId});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': 'P$id',
        'price': 5.0,
        'stock_quantity': stockQuantity,
        'store_id': storeId,
        'server_id': serverId,
      };
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

class _FakeSalesService extends SalesService {
  int? capturedStoreId;

  @override
  Future<Map<String, dynamic>> createSale(Map<String, dynamic> saleData,
      {int? storeId}) async {
    capturedStoreId = storeId;
    return {'transaction_id': 123};
  }
}

class FakeProductServiceWithAll extends ProductService {
  int callCount = 0;
  int callAllCount = 0;

  @override
  Future<List<Map<String, dynamic>>> getProducts({int? storeId}) async {
    callCount++;
    return [
      {'id': 1, 'name': 'P1', 'price': 10.0, 'stock_quantity': 5}
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getAllProducts(
      {bool includeInactive = false, int? storeId}) async {
    callAllCount++;
    return [
      {'id': 1, 'name': 'P1', 'price': 10.0, 'stock_quantity': 5}
    ];
  }
}

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
    // ensure the product service was called with the selected store id
    expect(fakeProd.lastStoreId, equals(2));
  });

  test('PosProvider requests global products when admin switches to All Stores',
      () async {
    final fakeProd = FakeProductService();
    final pos = PosProvider(productService: fakeProd);
    final storeProvider = StoreProvider(storeService: FakeStoreService());

    pos.setStoreProvider(storeProvider);

    // set to a specific store first so switching to All Stores is a state change
    final ok1 = await storeProvider.switchStore({'id': 1});
    expect(ok1, true);

    // ensure role allows All Stores
    SharedPreferences.setMockInitialValues({'user_role': 'admin'});

    // now switch to All Stores
    final ok0 = await storeProvider.switchStore({'id': 0});
    expect(ok0, true);

    // force load to avoid test-time race
    await pos.loadProducts();

    // fakeProd.getProducts should have been called with storeId == null
    expect(fakeProd.callCount, greaterThanOrEqualTo(1));
    expect(fakeProd.lastStoreId, isNull);
  });

  test('PosProvider includes all products from repository when on All Stores',
      () async {
    // Fake repository that returns products from stores 1 and 2
    final repo = FakeProductRepository([
      _FakeProduct(id: 1, storeId: 1, serverId: 1),
      _FakeProduct(id: 2, storeId: 2, serverId: 2),
    ]);

    final pos = PosProvider(productRepository: repo);
    final storeProvider = StoreProvider(storeService: FakeStoreService());
    pos.setStoreProvider(storeProvider);

    // set to a specific store first so switching to All Stores is a state change
    await storeProvider.switchStore({'id': 1});
    SharedPreferences.setMockInitialValues({'user_role': 'admin'});

    // now switch to All Stores
    SharedPreferences.setMockInitialValues({'user_role': 'admin'});

    // now switch to All Stores
    await storeProvider.switchStore({'id': 0});

    // force load to avoid test-time race
    await pos.loadProducts();

    expect(pos.availableProducts.length, 2);
  });

  test('PosProvider filters repository products on store switch', () async {
    // Two products in different stores
    final repo = FakeProductRepository([
      _FakeProduct(id: 1, storeId: 1, serverId: 1),
      _FakeProduct(id: 2, storeId: 2, serverId: 2),
    ]);

    final pos = PosProvider(productRepository: repo);
    final storeProvider = StoreProvider(storeService: FakeStoreService());
    pos.setStoreProvider(storeProvider);

    // switch to store 1
    await storeProvider.switchStore({'id': 1});
    await pos.loadProducts();
    expect(pos.availableProducts.length, 1);
    expect(pos.availableProducts.first['store_id'], equals(1));

    // switch to store 2 — listener should debounce and trigger reload
    await storeProvider.switchStore({'id': 2});
    await Future.delayed(const Duration(milliseconds: 200));
    expect(pos.availableProducts.length, 1);
    expect(pos.availableProducts.first['store_id'], equals(2));
  });

  test('PosProvider passes current store id to SalesService.createSale',
      () async {
    final fakeSales = _FakeSalesService();
    final pos = PosProvider(salesService: fakeSales);
    final storeProvider = StoreProvider(storeService: FakeStoreService());

    pos.setStoreProvider(storeProvider);

    // ensure store is set
    await storeProvider.switchStore({'id': 5});

    // Add an item to cart
    pos.addToCart({'id': 1, 'price': 10.0}, 2);

    final result = await pos.processSale('cash');
    expect(result['transaction_id'], equals(123));
    expect(fakeSales.capturedStoreId, equals(5));
  });
  test('PosProvider handles string-typed currentStore ids', () async {
    final fakeProd = FakeProductService();
    final pos = PosProvider(productService: fakeProd);

    // Create a tiny TestStoreProvider that reports id as a string
    final storeProvider = StoreProvider(storeService: FakeStoreService());
    // Manually set currentStore via the service's fake switch to ensure internal state
    await storeProvider.switchStore({'id': 2});

    // Forge a string-typed currentStore in the provider by directly setting user prefs
    // Simulate the edge case where store map contains a string id (e.g., backend or serialization quirk)
    // We'll replace the provider's currentStore by calling switchStore with a map where id is a string
    await storeProvider.switchStore({'id': '2'});

    pos.setStoreProvider(storeProvider);

    await pos.loadProducts();

    expect(fakeProd.lastStoreId, equals(2));
  });
  test('PosProvider uses getAllProducts when user is superadmin (service path)',
      () async {
    SharedPreferences.setMockInitialValues({'user_role': 'superadmin'});
    final fakeProd = FakeProductServiceWithAll();
    final pos = PosProvider(productService: fakeProd);
    final storeProvider = StoreProvider(storeService: FakeStoreService());

    pos.setStoreProvider(storeProvider);

    // set to a specific store first so switching to All Stores is a state change
    await storeProvider.switchStore({'id': 1});

    // now switch to All Stores
    await storeProvider.switchStore({'id': 0});

    // force load to avoid race conditions
    await pos.loadProducts();

    expect(fakeProd.callAllCount, greaterThanOrEqualTo(1));
  });
}
