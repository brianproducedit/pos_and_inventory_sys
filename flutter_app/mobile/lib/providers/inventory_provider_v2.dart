import 'dart:async';
import 'package:flutter/foundation.dart';
import '../db/app_database.dart';
import '../data/repositories/product_repository_v2.dart';
import 'store_provider.dart';
import 'auth_provider.dart';

/// V2 Inventory Provider - Uses offline-first repositories with streams
/// Replaces the V1 InventoryProvider with local-first architecture
class InventoryProviderV2 with ChangeNotifier {
  final ProductRepository_v2 _productRepo;
  StoreProvider? _storeProvider;
  AuthProvider? _authProvider;

  StreamSubscription<List<Product>>? _productsSubscription;
  StreamSubscription<List<Product>>? _lowStockSubscription;

  List<Product> _products = [];
  List<Product> _lowStockAlerts = [];
  bool _showInactiveProducts = false;
  String? _errorMessage;
  int? _lastStoreId;

  InventoryProviderV2(this._productRepo);

  // Getters
  List<Product> get products => _products;
  List<Product> get lowStockAlerts => _lowStockAlerts;
  int get lowStockCount => _lowStockAlerts.length;
  int get criticalLowStockCount =>
      _lowStockAlerts.where((p) => p.stockQuantity < 3).length;
  String? get errorMessage => _errorMessage;
  bool get showInactiveProducts => _showInactiveProducts;
  bool get isLoading => false; // Always false - data from local DB is instant

  /// Set store provider and listen to store changes
  void setStoreProvider(StoreProvider storeProvider) {
    if (_storeProvider != null) {
      _storeProvider!.removeListener(_onStoreChanged);
    }
    _storeProvider = storeProvider;
    _lastStoreId = _parseStoreId(_storeProvider?.currentStore?['id']);
    _storeProvider!.addListener(_onStoreChanged);
    _subscribeToProducts();
    _subscribeToLowStock();
  }

  /// Set auth provider for role-based filtering
  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
  }

  /// Parse store ID from various types
  int? _parseStoreId(dynamic id) {
    if (id == null) return null;
    if (id is int) return id;
    return int.tryParse(id.toString());
  }

  /// Handle store changes
  void _onStoreChanged() {
    final newId = _parseStoreId(_storeProvider?.currentStore?['id']);
    if (newId != _lastStoreId) {
      _lastStoreId = newId;
      _subscribeToProducts();
      _subscribeToLowStock();
    }
  }

  /// Subscribe to products stream from local database
  void _subscribeToProducts() {
    _productsSubscription?.cancel();
    
    final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);
    
    // Superadmin sees all products, others see store-filtered products
    final stream = (_authProvider?.role == 'superadmin')
        ? _productRepo.watchAll()
        : _productRepo.watchAll(storeId: storeId);

    _productsSubscription = stream.listen(
      (products) {
        _products = products.where((p) {
          // Filter by active status if needed
          if (!_showInactiveProducts && !p.isActive) return false;
          return true;
        }).toList();
        _errorMessage = null;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = 'Failed to load products: $error';
        debugPrint('InventoryProviderV2: Error loading products: $error');
        notifyListeners();
      },
    );
  }

  /// Subscribe to low stock alerts stream
  void _subscribeToLowStock() {
    _lowStockSubscription?.cancel();
    
    final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);
    
    final stream = _productRepo.watchLowStock(
      threshold: 5,
      storeId: storeId,
    );

    _lowStockSubscription = stream.listen(
      (products) {
        _lowStockAlerts = products;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('InventoryProviderV2: Error loading low stock: $error');
      },
    );
  }

  /// Toggle show inactive products
  void toggleShowInactiveProducts() {
    _showInactiveProducts = !_showInactiveProducts;
    _subscribeToProducts(); // Re-subscribe with new filter
  }

  /// Add new product (offline-first - writes to local DB immediately)
  Future<void> addProduct({
    required String name,
    String? description,
    String? sku,
    required double price,
    required int stockQuantity,
  }) async {
    _errorMessage = null;
    try {
      final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);
      if (storeId == null) {
        throw Exception('No store selected. Please select a store before adding a product.');
      }

      await _productRepo.create(
        name: name,
        description: description,
        sku: sku,
        price: price,
        stockQuantity: stockQuantity,
        storeId: storeId,
      );
      
      // No need to manually reload - stream will update automatically
      debugPrint('InventoryProviderV2: Product created successfully');
    } catch (e) {
      _errorMessage = 'Failed to add product: $e';
      debugPrint('InventoryProviderV2: Error adding product: $e');
      notifyListeners();
      rethrow;
    }
  }

  /// Update existing product (offline-first)
  Future<void> updateProduct(
    int productId, {
    String? name,
    String? description,
    String? sku,
    double? price,
    int? stockQuantity,
    bool? isActive,
  }) async {
    _errorMessage = null;
    try {
      await _productRepo.update(
        productId,
        name: name,
        description: description,
        sku: sku,
        price: price,
        stockQuantity: stockQuantity,
        isActive: isActive,
      );
      
      debugPrint('InventoryProviderV2: Product updated successfully');
    } catch (e) {
      _errorMessage = 'Failed to update product: $e';
      debugPrint('InventoryProviderV2: Error updating product: $e');
      notifyListeners();
      rethrow;
    }
  }

  /// Delete product (soft delete - marks as inactive)
  Future<void> deleteProduct(int productId) async {
    _errorMessage = null;
    try {
      await _productRepo.delete(productId);
      debugPrint('InventoryProviderV2: Product deleted successfully');
    } catch (e) {
      _errorMessage = 'Failed to delete product: $e';
      debugPrint('InventoryProviderV2: Error deleting product: $e');
      notifyListeners();
      rethrow;
    }
  }

  /// Update product status (activate/deactivate)
  Future<void> updateProductStatus(int productId, bool isActive) async {
    _errorMessage = null;
    try {
      if (isActive) {
        await _productRepo.activate(productId);
      } else {
        await _productRepo.deactivate(productId);
      }
      debugPrint('InventoryProviderV2: Product status updated successfully');
    } catch (e) {
      _errorMessage = 'Failed to update product status: $e';
      debugPrint('InventoryProviderV2: Error updating product status: $e');
      notifyListeners();
      rethrow;
    }
  }

  /// Update stock quantity
  Future<void> updateStock(int productId, int newQuantity) async {
    _errorMessage = null;
    try {
      await _productRepo.updateStock(productId, newQuantity);
      debugPrint('InventoryProviderV2: Stock updated successfully');
    } catch (e) {
      _errorMessage = 'Failed to update stock: $e';
      debugPrint('InventoryProviderV2: Error updating stock: $e');
      notifyListeners();
      rethrow;
    }
  }

  /// Search products by name or SKU
  Future<List<Product>> searchProducts(String query) async {
    try {
      final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);
      return await _productRepo.search(query, storeId: storeId);
    } catch (e) {
      debugPrint('InventoryProviderV2: Error searching products: $e');
      return [];
    }
  }

  /// Get product by ID
  Future<Product?> getProductById(int productId) async {
    try {
      return await _productRepo.getById(productId);
    } catch (e) {
      debugPrint('InventoryProviderV2: Error getting product: $e');
      return null;
    }
  }

  /// Get product by SKU
  Future<Product?> getProductBySku(String sku) async {
    try {
      return await _productRepo.getBySku(sku);
    } catch (e) {
      debugPrint('InventoryProviderV2: Error getting product by SKU: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _productsSubscription?.cancel();
    _lowStockSubscription?.cancel();
    if (_storeProvider != null) {
      _storeProvider!.removeListener(_onStoreChanged);
    }
    super.dispose();
  }
}
