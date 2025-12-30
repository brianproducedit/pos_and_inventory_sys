import '../../data/local/database_helper.dart';
import '../../data/remote/postgres_api_service.dart';
import '../../domain/models/product.dart';

class ProductRepository {
  final DatabaseHelper db;
  final PostgresApiService? api;

  ProductRepository({required this.db, this.api});

  Future<List<Product>> getAllProducts() async {
    final dbClient = await db.database;
    final rows = await dbClient.query('products');
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  /// Adds a product locally (atomic insert + queue entry) and returns local id.
  Future<int> addProduct(Product product) async {
    return await db.insertProduct(
      name: product.name,
      sku: product.sku,
      price: product.price,
      stockQuantity: product.stockQuantity,
      storeId: product.storeId,
    );
  }

  Future<int> updateStock(int localProductId, int newQuantity) async {
    return await db.updateStock(localProductId, newQuantity);
  }

  Future<int> updateProduct(
      int localProductId, Map<String, dynamic> fields) async {
    return await db.updateProduct(localProductId, fields);
  }

  Future<int> deleteProduct(int localProductId) async {
    return await db.deleteProduct(localProductId);
  }
}
