import 'dart:async';

import 'package:flutter/foundation.dart';
import '../services/product_service.dart';
import '../data/repositories/product_repository.dart';
import '../data/local/database_helper.dart';
import '../domain/models/product.dart' as domain_product;
import 'store_provider.dart';
import 'auth_provider.dart';
import 'sync_provider.dart';

class InventoryProvider with ChangeNotifier {
  final ProductService _productService;
  final ProductRepository? _productRepository;
  final DatabaseHelper? _dbHelper;
  SyncProvider? _syncProvider;

  InventoryProvider(
      {ProductService? productService,
      ProductRepository? productRepository,
      DatabaseHelper? dbHelper,
      SyncProvider? syncProvider})
      : _productService = productService ?? ProductService(),
        _productRepository = productRepository,
        _dbHelper = dbHelper,
        _syncProvider = syncProvider;

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _lowStockAlerts = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _showInactiveProducts = false;
  StoreProvider? _storeProvider;
  AuthProvider? _authProvider;

  int? _lastStoreId;

  int? _parseStoreId(dynamic id) {
    if (id == null) return null;
    if (id is int) return id;
    return int.tryParse(id.toString());
  }

  void _onStoreChanged() {
    final newId = _parseStoreId(_storeProvider?.currentStore?['id']);
    if (newId != _lastStoreId) {
      _lastStoreId = newId;
      // Fire a refresh to reflect the new store context
      unawaited(loadProducts());
      unawaited(loadLowStockAlerts());
    }
  }

  List<Map<String, dynamic>> get products => _products;
  List<Map<String, dynamic>> get lowStockAlerts => _lowStockAlerts;
  int get lowStockCount => _lowStockAlerts.length;
  int get criticalLowStockCount =>
      _lowStockAlerts.where((a) => a['alert_level'] == 'Critical').length;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get showInactiveProducts => _showInactiveProducts;

  /// Loads low-stock alerts for the current store (or all stores when current store is null).
  Future<void> loadLowStockAlerts() async {
    _errorMessage = null;
    try {
      final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);
      if (_productRepository != null) {
        final prods = await _productRepository!.getAllProducts();
        _lowStockAlerts = prods
            .where((p) =>
                p.stockQuantity < 5 &&
                (storeId == null || p.toMap()['store_id'] == storeId))
            .map((p) => p.toMap())
            .toList();
      } else {
        final alerts =
            await _productService.getLowStockAlerts(storeId: storeId);
        _lowStockAlerts = alerts;
      }
    } catch (e) {
      _errorMessage = 'Failed to load low stock alerts: $e';
      debugPrint('Error loading low stock alerts: $e');
    } finally {
      notifyListeners();
    }
  }

  void setStoreProvider(StoreProvider storeProvider) {
    if (_storeProvider != null) {
      _storeProvider!.removeListener(_onStoreChanged);
    }
    _storeProvider = storeProvider;
    _lastStoreId = _parseStoreId(_storeProvider?.currentStore?['id']);
    _storeProvider!.addListener(_onStoreChanged);
    // initial load of alerts for current store
    unawaited(loadLowStockAlerts());
  }

  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
  }

  void setSyncProvider(SyncProvider syncProvider) {
    _syncProvider = syncProvider;
  }

  Future<void> loadProducts() async {
    debugPrint('InventoryProvider.loadProducts: start');
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);
      if (_productRepository != null) {
        final prods =
            await _productRepository!.getAllProducts(storeId: storeId);
        debugPrint(
            'InventoryProvider.loadProducts: got ${prods.length} products from repo');
        final maps = prods.map((p) => p.toMap()).toList();
        // For non-superadmin users, show all products from current store (including locally added ones without server_id)
        // For superadmin, show only synced products (server_id != null) to avoid showing local-only products from other stores
        if (_authProvider?.role == 'superadmin') {
          _products = maps.where((m) => m['server_id'] != null).toList();
        } else {
          _products = maps;
        }
      } else {
        // Use existing ProductService
        // If superadmin, or admin has selected "All Stores" (store id == 0),
        // use getAllProducts so the server can return the union of accessible stores.
        final rawStoreId = _parseStoreId(_storeProvider?.currentStore?['id']);
        if (_authProvider?.role == 'superadmin' ||
            (_authProvider?.role == 'admin' && rawStoreId == 0)) {
          _products =
              await _productService.getAllProducts(includeInactive: false);
        } else {
          _products = await _productService.getProducts(storeId: storeId);
        }
      }

      // Also load low stock alerts for current store
      unawaited(loadLowStockAlerts());
    } catch (e) {
      _errorMessage = 'Failed to load products: $e';
      debugPrint('Error loading products: $e');
    } finally {
      _isLoading = false;
      debugPrint(
          'InventoryProvider.loadProducts: end, products=${_products.length}');
      notifyListeners();
    }
  }

  Future<void> addProduct(Map<String, dynamic> productData) async {
    _errorMessage = null;
    try {
      final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);
      if (storeId == null) {
        _errorMessage =
            'No store selected. Please select a store before adding a product.';
        debugPrint('Error adding product: no store selected');
        throw Exception(_errorMessage);
      }

      if (_productRepository != null) {
        // Use repository to insert locally and queue sync
        final newId =
            await _productRepository!.addProduct(domain_product.Product(
          name: productData['name'] as String? ?? '',
          sku: productData['sku'] as String? ??
              'SKU-${DateTime.now().millisecondsSinceEpoch}',
          price: (productData['price'] as num?)?.toDouble() ?? 0.0,
          stockQuantity: productData['stock_quantity'] as int? ?? 0,
          storeId: storeId,
        ));
        // Reload products to reflect new row
        await loadProducts();
        // Trigger sync to push changes to server
        unawaited(_syncProvider?.syncNow());
      } else {
        final newProduct =
            await _productService.createProduct(productData, storeId: storeId);
        _products.add(newProduct);
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to add product: $e';
      debugPrint('Error adding product: $e');
      rethrow;
    }
  }

  Future<void> updateProduct(
      int productId, Map<String, dynamic> productData) async {
    _errorMessage = null;
    try {
      final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);
      if (_productRepository != null) {
        await _productRepository!.updateProduct(productId, productData);
        // reload to reflect update
        await loadProducts();
        // Trigger sync to push changes to server
        unawaited(_syncProvider?.syncNow());
      } else {
        final updatedProduct = await _productService
            .updateProduct(productId, productData, storeId: storeId);
        final index = _products.indexWhere((p) => p['id'] == productId);
        if (index != -1) {
          _products[index] = updatedProduct;
          notifyListeners();
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to update product: $e';
      debugPrint('Error updating product: $e');
      rethrow;
    }
  }

  Future<void> deleteProduct(int productId) async {
    _errorMessage = null;
    try {
      if (_productRepository != null) {
        await _productRepository!.deleteProduct(productId);
        await loadProducts();
        // Trigger sync to push changes to server
        unawaited(_syncProvider?.syncNow());
      } else {
        final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);
        await _productService.deleteProduct(productId, storeId: storeId);
        _products.removeWhere((p) => p['id'] == productId);
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to delete product: $e';
      debugPrint('Error deleting product: $e');
      rethrow;
    }
  }

  Future<void> loadAllProducts({bool includeInactive = false}) async {
    _isLoading = true;
    _errorMessage = null;
    _showInactiveProducts = includeInactive;
    notifyListeners();

    try {
      final rawStoreId = _parseStoreId(_storeProvider?.currentStore?['id']);
      if (_authProvider?.role == 'superadmin' ||
          (_authProvider?.role == 'admin' && rawStoreId == 0)) {
        // Superadmin or admin with "All Stores" selected should get all products
        _products = await _productService.getAllProducts(
            includeInactive: includeInactive);
      } else {
        // Regular users see products filtered by current store
        final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);
        _products = await _productService.getAllProducts(
            includeInactive: includeInactive, storeId: storeId);
      }
    } catch (e) {
      _errorMessage = 'Failed to load products: $e';
      debugPrint('Error loading products: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateProductStatus(int productId, bool isActive) async {
    _errorMessage = null;
    try {
      final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);
      final updatedProduct = await _productService
          .updateProductStatus(productId, isActive, storeId: storeId);
      final index = _products.indexWhere((p) => p['id'] == productId);
      if (index != -1) {
        _products[index] = updatedProduct;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to update product status: $e';
      debugPrint('Error updating product status: $e');
      rethrow;
    }
  }

  void toggleShowInactiveProducts() {
    _showInactiveProducts = !_showInactiveProducts;
    loadAllProducts(includeInactive: _showInactiveProducts);
  }

  Future<int> cleanupOrphanedProducts() async {
    if (_dbHelper == null) return 0;
    try {
      final removedCount = await _dbHelper!.cleanupOrphanedProducts();
      // Reload products to reflect the cleanup
      await loadProducts();
      return removedCount;
    } catch (e) {
      _errorMessage = 'Failed to cleanup orphaned products: $e';
      debugPrint('Error cleaning up orphaned products: $e');
      notifyListeners();
      return 0;
    }
  }

  @override
  void dispose() {
    // Clean up listener on store provider to avoid leaks
    if (_storeProvider != null) {
      _storeProvider!.removeListener(_onStoreChanged);
    }
    super.dispose();
  }

  /// Test helper: set a simple current store without needing a full StoreProvider.
  void setCurrentStoreForTest(Map<String, dynamic> store) {
    _storeProvider = _DummyStoreProvider(store);
    _lastStoreId = store['id'] as int?;
  }
}

/// Internal lightweight store provider used only for tests and simple injections.
class _DummyStoreProvider extends StoreProvider {
  final Map<String, dynamic>? _store;
  _DummyStoreProvider(this._store) : super();

  @override
  Map<String, dynamic>? get currentStore => _store;

  @override
  void addListener(listener) {}

  @override
  void removeListener(listener) {}
}
