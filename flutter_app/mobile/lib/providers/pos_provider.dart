import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sales_service.dart';
import '../services/product_service.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/transaction_repository.dart';
import 'store_provider.dart';
import 'auth_provider.dart';
import 'sync_provider.dart';

class PosProvider with ChangeNotifier {
  final SalesService _salesService;
  final ProductService _productService;
  // Public getter to expose ProductService for testing or integrations
  ProductService get productService => _productService;
  final ProductRepository? _productRepository;
  final TransactionRepository? _transactionRepository;
  SyncProvider? _syncProvider;

  PosProvider(
      {SalesService? salesService,
      ProductService? productService,
      ProductRepository? productRepository,
      TransactionRepository? transactionRepository,
      SyncProvider? syncProvider})
      : _salesService = salesService ?? SalesService(),
        _productService = productService ?? ProductService(),
        _productRepository = productRepository,
        _transactionRepository = transactionRepository,
        _syncProvider = syncProvider;

  StoreProvider? _storeProvider;
  int? _lastStoreId;
  AuthProvider? _authProvider;

  // Debounce timer to avoid too-frequent reloads on store changes
  Timer? _reloadDebounce;

  // Normalize store id: treat 0 as global (null)
  int? _normalizeStoreId(int? id) => (id != null && id == 0) ? null : id;

  /// Optionally set an AuthProvider so the PosProvider can be role-aware
  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
  }

  void setSyncProvider(SyncProvider syncProvider) {
    _syncProvider = syncProvider;
  }

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

  int? _parseStoreId(dynamic id) {
    if (id == null) return null;
    if (id is int) return id;
    final parsed = int.tryParse(id.toString());
    return parsed;
  }

  void _onStoreChanged() {
    final rawId = _parseStoreId(_storeProvider?.currentStore?['id']);
    final newId = _normalizeStoreId(rawId);
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
    // Normalize stored id so comparisons are consistent (treat id==0 as null)
    _lastStoreId =
        _normalizeStoreId(_parseStoreId(_storeProvider?.currentStore?['id']));
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
      final storeId = _parseStoreId(_storeProvider?.currentStore?['id']);
      final int? normalizedId = _normalizeStoreId(storeId);

      // Determine role: prefer injected AuthProvider, otherwise consult prefs
      String? role = _authProvider?.role;
      if (role == null) {
        final prefs = await SharedPreferences.getInstance();
        role = prefs.getString('user_role')?.toLowerCase();
      }

      // If we have a local repository, use it and apply role-aware behavior
      if (_productRepository != null) {
        final prods =
            await _productRepository!.getAllProducts(storeId: normalizedId);
        final maps = prods.map((p) => p.toMap()).toList();
        // Filter out products that haven't been synced to the server (server_id is null)
        final syncedProducts =
            maps.where((m) => m['server_id'] != null).toList();
        final rawStoreId = _parseStoreId(_storeProvider?.currentStore?['id']);
        if (role == 'superadmin' || (role == 'admin' && rawStoreId == 0)) {
          // Superadmin or admin on All Stores sees all synced products
          _availableProducts = syncedProducts;
        } else {
          // Non-admin: show all products from current store (including locally added ones without server_id)
          if (rawStoreId == null) {
            _availableProducts = [];
          } else {
            _availableProducts =
                maps.where((m) => m['store_id'] == rawStoreId).toList();
          }
        }
      } else {
        // Service-backed path: superadmin should use the all endpoint
        if (role == 'superadmin') {
          _availableProducts =
              await _productService.getAllProducts(includeInactive: false);
        } else {
          final rawStoreId = _parseStoreId(_storeProvider?.currentStore?['id']);
          final int? normalizedForService = _normalizeStoreId(rawStoreId);
          _availableProducts = await _product_service_getProducts_with_store(
              normalizedForService);
        }
      }
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
      if (_transactionRepository != null && _productRepository != null) {
        // Get store_id and user_id for the transaction
        final storeIdRaw = _parseStoreId(_storeProvider?.currentStore?['id']);
        final storeId = _normalizeStoreId(storeIdRaw);
        final userId = _authProvider?.userId;

        debugPrint(
            'PosProvider.processSale: creating transaction with storeId=$storeId, userId=$userId');

        // Create transaction locally and update local stock (offline-first)
        final txId = await _transactionRepository!.addTransaction(
          transactionNumber: 'TX-${DateTime.now().millisecondsSinceEpoch}',
          totalAmount: _total,
          paymentMethod: paymentMethod,
          items: _cart
              .map((item) => {
                    'product_id': item['product']['id'],
                    'quantity': item['quantity'],
                    'price': item['unit_price'],
                  })
              .toList(),
          storeId: storeId,
          userId: userId,
        );

        // Update stock for each product locally
        for (final item in _cart) {
          final pid = item['product']['id'] as int;
          final qty = item['quantity'] as int;

          // Decrement stock by quantity
          // Fetch current product (could be optimized)
          final prods = await _productRepository!.getAllProducts();
          final prod = prods.firstWhere((p) => p.id == pid,
              orElse: () => throw Exception('Product not found'));
          final newQty = prod.stockQuantity - qty;
          await _productRepository!.updateStock(pid, newQty);
        }

        clearCart();
        await loadProducts();
        // Trigger sync to push transaction and stock changes to server
        unawaited(_syncProvider?.syncNow());
        return {'transaction_id': txId};
      } else {
        final storeIdRaw = _parseStoreId(_storeProvider?.currentStore?['id']);
        final storeId = _normalizeStoreId(storeIdRaw);
        final result =
            await _salesService.createSale(saleData, storeId: storeId);
        clearCart(); // Clear cart after successful sale
        await loadProducts(); // Refresh products to update stock
        return result;
      }
    } catch (e) {
      _errorMessage = 'Failed to process sale: $e';
      debugPrint('Error processing sale: $e');
      rethrow;
    }
  }
}
