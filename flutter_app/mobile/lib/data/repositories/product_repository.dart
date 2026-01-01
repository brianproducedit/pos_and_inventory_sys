import '../../data/local/database_helper.dart';
import '../../data/remote/postgres_api_service.dart';
import '../../domain/models/product.dart';

class ProductRepository {
  final DatabaseHelper db;
  final PostgresApiService? api;

  ProductRepository({required this.db, this.api});

  Future<void> _forceReinitializeDatabase() async {
    // Force the DatabaseHelper to reinitialize by clearing its static reference
    // This is handled by calling db.database which checks if the connection is open
    // and will reinitialize if needed. We don't close it here to avoid race conditions
    // with other concurrent operations that might be using the database.
    try {
      // Just verify the database is accessible - the getter will reinitialize if closed
      await db.database;
    } catch (e) {
      // Ignore errors when trying to verify - next call will attempt reinitialization
      print(
          'Warning: Database verification failed during reinitialization attempt: $e');
    }
  }

  Future<List<Product>> getAllProducts({int? storeId}) async {
    try {
      final dbClient = await db.database;
      final rows = storeId != null
          ? await dbClient
              .query('products', where: 'store_id = ?', whereArgs: [storeId])
          : await dbClient.query('products');
      return rows.map((r) => Product.fromMap(r)).toList();
    } catch (e) {
      // If database error, try once more after reinitializing
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('database') ||
          errorMessage.contains('sqlite')) {
        // Force database reinitialization by clearing the static reference
        // This ensures we get a fresh database connection
        await _forceReinitializeDatabase();
        final dbClient = await db.database;
        final rows = storeId != null
            ? await dbClient
                .query('products', where: 'store_id = ?', whereArgs: [storeId])
            : await dbClient.query('products');
        return rows.map((r) => Product.fromMap(r)).toList();
      }
      rethrow;
    }
  }

  /// Adds a product locally (atomic insert + queue entry) and returns local id.
  Future<int> addProduct(Product product) async {
    try {
      return await db.insertProduct(
        name: product.name,
        sku: product.sku,
        price: product.price,
        stockQuantity: product.stockQuantity,
        storeId: product.storeId,
      );
    } catch (e) {
      // If database error, try once more after reinitializing
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('database') ||
          errorMessage.contains('sqlite')) {
        await _forceReinitializeDatabase();
        return await db.insertProduct(
          name: product.name,
          sku: product.sku,
          price: product.price,
          stockQuantity: product.stockQuantity,
          storeId: product.storeId,
        );
      }
      rethrow;
    }
  }

  Future<int> updateStock(int localProductId, int newQuantity) async {
    try {
      return await db.updateStock(localProductId, newQuantity);
    } catch (e) {
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('database') ||
          errorMessage.contains('sqlite')) {
        await _forceReinitializeDatabase();
        return await db.updateStock(localProductId, newQuantity);
      }
      rethrow;
    }
  }

  Future<int> updateProduct(
      int localProductId, Map<String, dynamic> fields) async {
    try {
      return await db.updateProduct(localProductId, fields);
    } catch (e) {
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('database') ||
          errorMessage.contains('sqlite')) {
        await _forceReinitializeDatabase();
        return await db.updateProduct(localProductId, fields);
      }
      rethrow;
    }
  }

  Future<int> deleteProduct(int localProductId) async {
    try {
      return await db.deleteProduct(localProductId);
    } catch (e) {
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('database') ||
          errorMessage.contains('sqlite')) {
        await _forceReinitializeDatabase();
        return await db.deleteProduct(localProductId);
      }
      rethrow;
    }
  }
}
