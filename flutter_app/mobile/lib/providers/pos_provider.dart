import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/sales_service.dart';
import '../services/product_service.dart';
import 'store_provider.dart';

class PosProvider with ChangeNotifier {
  final SalesService _salesService;
  final ProductService _productService;

  PosProvider({SalesService? salesService, ProductService? productService})
      : _salesService = salesService ?? SalesService(),
        _productService = productService ?? ProductService();

  StoreProvider? _storeProvider;
  int? _lastStoreId;

  // Debounce timer to avoid too-frequent reloads on store changes
  Timer? _reloadDebounce;

  final List<Map<String, dynamic>> _cart = [];
  List<Map<String, dynamic>> _availableProducts = [];
  bool _isLoading = false;
  double _total = 0.0;
  String? _errorMessage;

  List<Map<String, dynamic>> get cart => _cart;
  List<Map<String, dynamic>> get availableProducts => _availableProducts;
  bool get isLoading => _isLoading;
  double get total => _total;
  String? get errorMessage => _errorMessage;

  void _onStoreChanged() {
    final newId = _storeProvider?.currentStore?['id'] as int?;
    if (newId != _lastStoreId) {
      _lastStoreId = newId;
      // Debounce reload to avoid multiple rapid calls
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 150), () {
        loadProducts();
      });
    }
  }

  void setStoreProvider(StoreProvider storeProvider) {
    if (_storeProvider != null) {
      _storeProvider!.removeListener(_onStoreChanged);
    }
    _storeProvider = storeProvider;
    _lastStoreId = _storeProvider?.currentStore?['id'] as int?;
    _storeProvider!.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    if (_storeProvider != null) _storeProvider!.removeListener(_onStoreChanged);
    super.dispose();
  }

  Future<void> loadProducts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final storeId = _storeProvider?.currentStore?['id'] as int?;
      _availableProducts =
          await _product_service_getProducts_with_store(storeId);
    } catch (e) {
      _errorMessage = 'Failed to load products: $e';
      debugPrint('Error loading products: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Helper to call ProductService.getProducts with store id
  Future<List<Map<String, dynamic>>> _product_service_getProducts_with_store(
      int? storeId) async {
    return await _productService.getProducts(storeId: storeId);
  }

  void addToCart(Map<String, dynamic> product, int quantity) {
    final existingIndex =
        _cart.indexWhere((item) => item['product']['id'] == product['id']);

    if (existingIndex != -1) {
      _cart[existingIndex]['quantity'] += quantity;
    } else {
      _cart.add({
        'product': product,
        'quantity': quantity,
        'unit_price': product['price'],
      });
    }
    _calculateTotal();
    notifyListeners();
  }

  void removeFromCart(int productId) {
    _cart.removeWhere((item) => item['product']['id'] == productId);
    _calculateTotal();
    notifyListeners();
  }

  void updateQuantity(int productId, int quantity) {
    final index =
        _cart.indexWhere((item) => item['product']['id'] == productId);
    if (index != -1) {
      if (quantity <= 0) {
        _cart.removeAt(index);
      } else {
        _cart[index]['quantity'] = quantity;
      }
      _calculateTotal();
      notifyListeners();
    }
  }

  void _calculateTotal() {
    _total = _cart.fold(0.0, (sum, item) {
      return sum + (item['quantity'] * item['unit_price']);
    });
  }

  void clearCart() {
    _cart.clear();
    _total = 0.0;
    notifyListeners();
  }

  Future<Map<String, dynamic>> processSale(String paymentMethod) async {
    if (_cart.isEmpty) throw Exception('Cart is empty');

    _errorMessage = null;
    final saleData = {
      'items': _cart
          .map((item) => {
                'product_id': item['product']['id'],
                'quantity': item['quantity'],
                'unit_price': item['unit_price'],
              })
          .toList(),
      'total_amount': _total,
      'payment_method': paymentMethod,
    };

    try {
      final result = await _salesService.createSale(saleData);
      clearCart(); // Clear cart after successful sale
      await loadProducts(); // Refresh products to update stock
      return result;
    } catch (e) {
      _errorMessage = 'Failed to process sale: $e';
      debugPrint('Error processing sale: $e');
      rethrow;
    }
  }
}
