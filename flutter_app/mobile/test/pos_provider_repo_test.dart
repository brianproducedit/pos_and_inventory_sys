import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'package:mobile/data/remote/postgres_api_service.dart';
import 'package:mobile/providers/pos_provider.dart';
import 'package:mobile/data/repositories/transaction_repository.dart';
import 'package:mobile/data/repositories/product_repository.dart';
import 'package:mobile/domain/models/product.dart';

class FakeTransactionRepo implements TransactionRepository {
  @override
  final DatabaseHelper db = DatabaseHelper();
  @override
  final PostgresApiService? api = null;

  bool addCalled = false;

  @override
  Future<int> addTransaction(
      {required String transactionNumber,
      required double totalAmount,
      required String paymentMethod,
      required List<Map<String, dynamic>> items}) async {
    addCalled = true;
    return 100;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllTransactions() async {
    return [];
  }
}

class FakeProductRepo implements ProductRepository {
  @override
  final DatabaseHelper db = DatabaseHelper();
  @override
  final PostgresApiService? api = null;

  bool updateCalled = false;
  bool getAllCalled = false;

  @override
  Future<int> addProduct(product) async => 1;

  @override
  Future<List<Product>> getAllProducts() async {
    getAllCalled = true;
    return [
      Product(id: 1, name: 'Test', sku: 'T1', price: 10.0, stockQuantity: 10)
    ];
  }

  @override
  Future<int> updateStock(int localProductId, int newQuantity) async {
    updateCalled = true;
    return 1;
  }

  @override
  Future<int> updateProduct(
      int localProductId, Map<String, dynamic> fields) async {
    // Simulate update
    return 1;
  }

  @override
  Future<int> deleteProduct(int localProductId) async {
    // Simulate delete
    return 1;
  }
}

void main() {
  test('PosProvider uses transaction repo and product repo when provided',
      () async {
    final fakeTx = FakeTransactionRepo();
    final fakeProd = FakeProductRepo();
    final provider =
        PosProvider(productRepository: fakeProd, transactionRepository: fakeTx);

    // Add an item to cart (simulate available product map structure)
    provider.addToCart({'id': 1, 'price': 10.0}, 1);

    final res = await provider.processSale('cash');
    expect(fakeTx.addCalled, isTrue);
    expect(fakeProd.updateCalled, isTrue);
  });
}
