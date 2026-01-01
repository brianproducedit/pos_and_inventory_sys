import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'package:mobile/data/remote/postgres_api_service.dart';
import 'package:mobile/providers/inventory_provider.dart';
import 'package:mobile/data/repositories/product_repository.dart';
import 'package:mobile/domain/models/product.dart';

class FakeProductRepo implements ProductRepository {
  @override
  final DatabaseHelper db = DatabaseHelper();
  @override
  final PostgresApiService? api = null;

  bool addCalled = false;
  bool getAllCalled = false;

  @override
  Future<int> addProduct(Product product) async {
    addCalled = true;
    return 42;
  }

  @override
  Future<List<Product>> getAllProducts({int? storeId}) async {
    getAllCalled = true;
    return [Product(id: 1, name: 'A', sku: 'A1', price: 1.0, stockQuantity: 2)];
  }

  @override
  Future<int> updateStock(int localProductId, int newQuantity) async {
    return 1;
  }

  @override
  Future<int> updateProduct(
      int localProductId, Map<String, dynamic> fields) async {
    return 1;
  }

  @override
  Future<int> deleteProduct(int localProductId) async {
    return 1;
  }
}

void main() {
  test('InventoryProvider uses repository for add and load', () async {
    final fake = FakeProductRepo();
    final provider = InventoryProvider(productRepository: fake);

    // Provide a store context to allow addProduct to proceed
    provider.setCurrentStoreForTest({'id': 1, 'name': 'Test Store'});

    await provider
        .addProduct({'name': 'Test', 'price': 1.0, 'stock_quantity': 0});
    expect(fake.addCalled, isTrue);

    await provider.loadProducts();
    expect(fake.getAllCalled, isTrue);
  });
}
