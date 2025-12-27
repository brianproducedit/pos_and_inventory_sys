import 'dart:async';

import 'package:flutter/foundation.dart';
import '../services/product_service.dart';
import 'store_provider.dart';
import 'auth_provider.dart';

class InventoryProvider with ChangeNotifier {
  final ProductService _productService;

  InventoryProvider({ProductService? productService})
      : _productService = productService ?? ProductService();
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _lowStockAlerts = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _showInactiveProducts = false;
  StoreProvider? _storeProvider;
  AuthProvider? _authProvider;

  int? _lastStoreId;

  void _onStoreChanged() {
    final newId = _storeProvider?.currentStore?['id'] as int?;
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
      final storeId = _storeProvider?.currentStore?['id'] as int?;
      final alerts = await _productService.getLowStockAlerts(storeId: storeId);
      _lowStockAlerts = alerts;
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
    _lastStoreId = _storeProvider?.currentStore?['id'] as int?;
    _storeProvider!.addListener(_onStoreChanged);
    // initial load of alerts for current store
    unawaited(loadLowStockAlerts());
  }

  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
  }

  Future<void> loadProducts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Use role-based access control for product loading
      if (_authProvider?.role == 'superadmin') {
        // Superadmin can see all products across stores
        _products =
            await _productService.getAllProducts(includeInactive: false);
      } else {
        // Regular users see products filtered by current store
        final storeId = _storeProvider?.currentStore?['id'];
        _products = await _productService.getProducts(storeId: storeId);
      }

      // Also load low stock alerts for current store
      unawaited(loadLowStockAlerts());
    } catch (e) {
      _errorMessage = 'Failed to load products: $e';
      debugPrint('Error loading products: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addProduct(Map<String, dynamic> productData) async {
    _errorMessage = null;
    try {
      final storeId = _storeProvider?.currentStore?['id'];
      if (storeId == null) {
        _errorMessage =
            'No store selected. Please select a store before adding a product.';
        debugPrint('Error adding product: no store selected');
        throw Exception(_errorMessage);
      }

      final newProduct =
          await _productService.createProduct(productData, storeId: storeId);
      _products.add(newProduct);
      notifyListeners();
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
      final storeId = _storeProvider?.currentStore?['id'];
      final updatedProduct = await _productService
          .updateProduct(productId, productData, storeId: storeId);
      final index = _products.indexWhere((p) => p['id'] == productId);
      if (index != -1) {
        _products[index] = updatedProduct;
        notifyListeners();
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
      final storeId = _storeProvider?.currentStore?['id'];
      await _productService.deleteProduct(productId, storeId: storeId);
      _products.removeWhere((p) => p['id'] == productId);
      notifyListeners();
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
      if (_authProvider?.role == 'superadmin') {
        // Superadmin can see all products across stores
        _products = await _productService.getAllProducts(
            includeInactive: includeInactive);
      } else {
        // Regular users see products filtered by current store
        final storeId = _storeProvider?.currentStore?['id'];
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
      final storeId = _storeProvider?.currentStore?['id'];
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

  @override
  void dispose() {
    // Clean up listener on store provider to avoid leaks
    if (_storeProvider != null) {
      _storeProvider!.removeListener(_onStoreChanged);
    }
    super.dispose();
  }
}
