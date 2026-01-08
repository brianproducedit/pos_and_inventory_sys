import 'dart:async';
import 'package:flutter/foundation.dart';
import '../db/app_database.dart';
import '../data/repositories/product_repository_v2.dart';
import '../data/repositories/sale_repository_v2.dart';
import 'store_provider.dart';
import 'auth_provider.dart';

/// V2 POS Provider - Uses offline-first repositories with streams
/// Replaces V1 PosProvider with local-first architecture for instant cart operations
class PosProviderV2 with ChangeNotifier {
  final ProductRepository _productRepo;
  final SaleRepository _saleRepo;
  StoreProvider? _storeProvider;
  AuthProvider? _authProvider;

  StreamSubscription<List<Product>>? _productsSubscription;

  List<Product> _availableProducts = [];
  final List<CartItem> _cart = [];
  String? _errorMessage;
  int? _lastStoreId;

  PosProviderV2(this._productRepo, this._saleRepo);

  // Getters
  List<Product> get availableProducts => _availableProducts;
  List<CartItem> get cart => _cart;
  String? get errorMessage => _errorMessage;
  bool get isLoading => false; // Always false - local DB is instant

  double get total =>
      _cart.fold(0.0, (sum, item) => sum + (item.quantity * item.unitPrice));

  int get itemCount => _cart.fold(0, (sum, item) => sum + item.quantity);

  /// Set store provider and listen to store changes
  void setStoreProvider(StoreProvider storeProvider) {
    if (_storeProvider != null) {
      _storeProvider!.removeListener(_onStoreChanged);
    }
    _storeProvider = storeProvider;
    _lastStoreId = _parseStoreId(_storeProvider?.currentStore?['id']);
    _storeProvider!.addListener(_onStoreChanged);
    _subscribeToProducts();
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
    }
  }

  /// Subscribe to products stream from local database
  void _subscribeToProducts() {
    _productsSubscription?.cancel();

    final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);

    // Superadmin sees all products, others see store-filtered products
    final stream = (_authProvider?.role == UserRole.superadmin)
        ? _productRepo.watchAll()
        : _productRepo.watchAll(storeId: storeId);

    _productsSubscription = stream.listen(
      (products) {
        // Only show active products in POS
        _availableProducts = products.where((p) => p.isActive).toList();
        _errorMessage = null;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = 'Failed to load products: $error';
        debugPrint('PosProviderV2: Error loading products: $error');
        notifyListeners();
      },
    );
  }

  /// Add product to cart
  void addToCart(Product product, int quantity) {
    if (quantity <= 0) return;

    _errorMessage = null;
    final existingIndex =
        _cart.indexWhere((item) => item.productId == product.id);

    if (existingIndex != -1) {
      _cart[existingIndex] = CartItem(
        productId: product.id,
        productName: product.name,
        quantity: _cart[existingIndex].quantity + quantity,
        unitPrice: product.price,
      );
    } else {
      _cart.add(CartItem(
        productId: product.id,
        productName: product.name,
        quantity: quantity,
        unitPrice: product.price,
      ));
    }
    notifyListeners();
  }

  /// Remove product from cart
  void removeFromCart(int productId) {
    _cart.removeWhere((item) => item.productId == productId);
    notifyListeners();
  }

  /// Update quantity for a cart item
  void updateQuantity(int productId, int quantity) {
    if (quantity <= 0) {
      removeFromCart(productId);
      return;
    }

    final index = _cart.indexWhere((item) => item.productId == productId);
    if (index != -1) {
      _cart[index] = CartItem(
        productId: _cart[index].productId,
        productName: _cart[index].productName,
        quantity: quantity,
        unitPrice: _cart[index].unitPrice,
      );
      notifyListeners();
    }
  }

  /// Clear entire cart
  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  /// Process sale (offline-first - writes to local DB immediately)
  Future<int> processSale(String paymentMethod) async {
    if (_cart.isEmpty) {
      throw Exception('Cart is empty');
    }

    _errorMessage = null;

    try {
      final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);
      if (storeId == null) {
        throw Exception(
            'No store selected. Please select a store before processing sale.');
      }

      final userId = _parseUserId(_authProvider?.userId);
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Create sale items list with proper type
      final items = _cart
          .map((item) => SaleItemData(
                productId: item.productId,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
              ))
          .toList();

      // Complete sale in local database (instant, atomic transaction)
      final sale = await _saleRepo.completeSale(
        userId: userId,
        storeId: storeId,
        totalAmount: total,
        paymentMethod: paymentMethod,
        items: items,
      );

      // Clear cart after successful sale
      clearCart();

      debugPrint('PosProviderV2: Sale ${sale.id} created successfully');
      return sale.id;
    } catch (e) {
      _errorMessage = 'Failed to process sale: $e';
      debugPrint('PosProviderV2: Error processing sale: $e');
      notifyListeners();
      rethrow;
    }
  }

  /// Parse user ID from various types
  int? _parseUserId(dynamic id) {
    if (id == null) return null;
    if (id is int) return id;
    return int.tryParse(id.toString());
  }

  /// Get product by ID (for quick lookups)
  Product? getProductById(int productId) {
    try {
      return _availableProducts.firstWhere((p) => p.id == productId);
    } catch (_) {
      return null;
    }
  }

  /// Search products by name or SKU
  List<Product> searchProducts(String query) {
    if (query.isEmpty) return _availableProducts;

    final lowerQuery = query.toLowerCase();
    return _availableProducts.where((p) {
      return p.name.toLowerCase().contains(lowerQuery) ||
          (p.sku?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  @override
  void dispose() {
    _productsSubscription?.cancel();
    if (_storeProvider != null) {
      _storeProvider!.removeListener(_onStoreChanged);
    }
    super.dispose();
  }
}

/// Cart item model for type safety
class CartItem {
  final int productId;
  final String productName;
  final int quantity;
  final double unitPrice;

  CartItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  double get lineTotal => quantity * unitPrice;

  CartItem copyWith({
    int? productId,
    String? productName,
    int? quantity,
    double? unitPrice,
  }) {
    return CartItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }
}
