import 'package:flutter/material.dart';
import '../db/app_database.dart';
import '../data/repositories/product_repository_v2.dart';

/// Cart item model
class CartItem {
  final Product product;
  int quantity;
  double get subtotal => product.price * quantity;

  CartItem({
    required this.product,
    this.quantity = 1,
  });

  CartItem copyWith({
    Product? product,
    int? quantity,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
    );
  }
}

/// Provider for managing shopping cart state
/// Fully functional offline - no network dependency
class CartProvider with ChangeNotifier {
  final ProductRepository productRepository;
  final List<CartItem> _items = [];

  CartProvider({required this.productRepository});

  List<CartItem> get items => List.unmodifiable(_items);
  int get itemCount => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  /// Get total number of products in cart (sum of quantities)
  int get totalQuantity => _items.fold(0, (sum, item) => sum + item.quantity);

  /// Get cart subtotal
  double get subtotal => _items.fold(0, (sum, item) => sum + item.subtotal);

  /// Get tax amount (based on settings - to be implemented)
  double getTax({double taxRate = 0.0}) => subtotal * taxRate;

  /// Get total amount (subtotal + tax)
  double getTotal({double taxRate = 0.0}) =>
      subtotal + getTax(taxRate: taxRate);

  /// Add product to cart
  Future<bool> addProduct(Product product, {int quantity = 1}) async {
    // Check if product has sufficient stock
    if (product.stockQuantity < quantity) {
      return false; // Insufficient stock
    }

    // Check if product already in cart
    final existingIndex =
        _items.indexWhere((item) => item.product.id == product.id);

    if (existingIndex != -1) {
      // Product already in cart, increase quantity
      final newQuantity = _items[existingIndex].quantity + quantity;

      // Check total quantity against stock
      if (newQuantity > product.stockQuantity) {
        return false; // Would exceed available stock
      }

      _items[existingIndex].quantity = newQuantity;
    } else {
      // Add new item to cart
      _items.add(CartItem(product: product, quantity: quantity));
    }

    notifyListeners();
    return true;
  }

  /// Update item quantity
  Future<bool> updateQuantity(int productId, int newQuantity) async {
    if (newQuantity <= 0) {
      return removeProduct(productId);
    }

    final index = _items.indexWhere((item) => item.product.id == productId);
    if (index == -1) return false;

    final product = _items[index].product;

    // Check against available stock
    if (newQuantity > product.stockQuantity) {
      return false; // Insufficient stock
    }

    _items[index].quantity = newQuantity;
    notifyListeners();
    return true;
  }

  /// Increase item quantity by 1
  Future<bool> incrementQuantity(int productId) async {
    final index = _items.indexWhere((item) => item.product.id == productId);
    if (index == -1) return false;

    final currentQuantity = _items[index].quantity;
    return await updateQuantity(productId, currentQuantity + 1);
  }

  /// Decrease item quantity by 1
  Future<bool> decrementQuantity(int productId) async {
    final index = _items.indexWhere((item) => item.product.id == productId);
    if (index == -1) return false;

    final currentQuantity = _items[index].quantity;
    if (currentQuantity <= 1) {
      return removeProduct(productId);
    }

    return await updateQuantity(productId, currentQuantity - 1);
  }

  /// Remove product from cart
  bool removeProduct(int productId) {
    final index = _items.indexWhere((item) => item.product.id == productId);
    if (index == -1) return false;

    _items.removeAt(index);
    notifyListeners();
    return true;
  }

  /// Clear entire cart
  void clear() {
    _items.clear();
    notifyListeners();
  }

  /// Get cart item by product ID
  CartItem? getItem(int productId) {
    try {
      return _items.firstWhere((item) => item.product.id == productId);
    } catch (_) {
      return null;
    }
  }

  /// Check if product is in cart
  bool contains(int productId) {
    return _items.any((item) => item.product.id == productId);
  }

  /// Get quantity of specific product in cart
  int getProductQuantity(int productId) {
    final item = getItem(productId);
    return item?.quantity ?? 0;
  }

  /// Validate cart against current stock levels
  /// Returns list of products with insufficient stock
  Future<List<String>> validateStock() async {
    final errors = <String>[];

    for (final item in _items) {
      // Refresh product data from database
      final currentProduct = await productRepository.getById(item.product.id);

      if (currentProduct == null) {
        errors.add('${item.product.name} is no longer available');
        continue;
      }

      if (!currentProduct.isActive) {
        errors.add('${item.product.name} is no longer available');
        continue;
      }

      if (currentProduct.stockQuantity < item.quantity) {
        errors.add(
          '${item.product.name}: Only ${currentProduct.stockQuantity} available (need ${item.quantity})',
        );
      }
    }

    return errors;
  }

  /// Refresh all products in cart with latest data from database
  Future<void> refreshProducts() async {
    for (int i = 0; i < _items.length; i++) {
      final currentProduct =
          await productRepository.getById(_items[i].product.id);
      _items[i] = _items[i].copyWith(product: currentProduct);
    }
    notifyListeners();
  }

  /// Apply discount to cart
  double applyDiscount({
    double? percentageDiscount,
    double? fixedDiscount,
  }) {
    if (percentageDiscount != null) {
      return subtotal * (percentageDiscount / 100);
    } else if (fixedDiscount != null) {
      return fixedDiscount > subtotal ? subtotal : fixedDiscount;
    }
    return 0.0;
  }

  /// Get final amount after discount
  double getFinalTotal({
    double taxRate = 0.0,
    double? percentageDiscount,
    double? fixedDiscount,
  }) {
    final discountAmount = applyDiscount(
      percentageDiscount: percentageDiscount,
      fixedDiscount: fixedDiscount,
    );
    final afterDiscount = subtotal - discountAmount;
    final tax = afterDiscount * taxRate;
    return afterDiscount + tax;
  }

  /// Prepare cart data for sale completion
  List<Map<String, dynamic>> toSaleItems() {
    return _items.map((item) {
      return {
        'product_id': item.product.id,
        'quantity': item.quantity,
        'unit_price': item.product.price,
        'total_price': item.subtotal,
      };
    }).toList();
  }

  /// Get cart summary for display
  Map<String, dynamic> getSummary({double taxRate = 0.0}) {
    return {
      'item_count': itemCount,
      'total_quantity': totalQuantity,
      'subtotal': subtotal,
      'tax': getTax(taxRate: taxRate),
      'total': getTotal(taxRate: taxRate),
      'items': _items.map((item) {
        return {
          'product_name': item.product.name,
          'quantity': item.quantity,
          'unit_price': item.product.price,
          'subtotal': item.subtotal,
        };
      }).toList(),
    };
  }

  /// Save cart state (for recovery after app restart)
  Map<String, dynamic> toJson() {
    return {
      'items': _items.map((item) {
        return {
          'product_id': item.product.id,
          'quantity': item.quantity,
        };
      }).toList(),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Restore cart from saved state
  Future<void> fromJson(Map<String, dynamic> json) async {
    _items.clear();

    final itemsData = json['items'] as List<dynamic>;
    for (final itemData in itemsData) {
      try {
        final productId = itemData['product_id'] as int;
        final quantity = itemData['quantity'] as int;

        final product = await productRepository.getById(productId);

        if (product != null && product.isActive && product.stockQuantity >= quantity) {
          _items.add(CartItem(product: product, quantity: quantity));
        }
      } catch (e) {
        // Skip invalid items
        debugPrint('Failed to restore cart item: $e');
      }
    }

    notifyListeners();
  }
}
