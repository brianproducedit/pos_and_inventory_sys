import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/pos_provider_v2.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/sync_provider.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:mobile/widgets/store_badge.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:mobile/widgets/product_card.dart';
import 'package:mobile/widgets/primary_button.dart';
import 'package:mobile/db/app_database.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with WidgetsBindingObserver {
  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // V2: Setup providers - products load automatically via streams
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final posProvider = context.read<PosProviderV2>();
      final storeProvider = context.read<StoreProvider>();

      try {
        if (!storeProvider.isInitialized) {
          unawaited(storeProvider.initialize());
        }
      } catch (e) {
        debugPrint('PosScreen: store init skipped: $e');
      }
      posProvider.setStoreProvider(storeProvider);

      // Set auth provider for role-aware product loading
      final auth = context.read<AuthProvider>();
      posProvider.setAuthProvider(auth);

      // Prevent non-admins from being left on All Stores: fallback to myStore if needed
      if (storeProvider.currentStore == null &&
          auth.role != UserRole.superadmin &&
          auth.role != UserRole.admin) {
        if (storeProvider.myStores.isNotEmpty) {
          await storeProvider.switchStore(storeProvider.myStores.first);
        }
      }
      // V2: No manual loadProducts() needed - streams handle it
    });
  }

  // V2: No need to reload on resume - streams keep data fresh automatically

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('POS'),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                StoreIndicator(
                    store: context.watch<StoreProvider>().currentStore),
                Row(
                  children: [
                    if (context.watch<AuthProvider>().role ==
                            UserRole.superadmin ||
                        context.watch<AuthProvider>().role == UserRole.admin)
                      const StoreQuickAction(),
                    // V2: Refresh button removed - streams auto-update
                    Consumer<PosProviderV2>(
                      builder: (context, posProvider, child) {
                        return IconButton(
                          tooltip: 'Open cart',
                          icon: const Icon(Icons.shopping_cart,
                              color: Colors.white),
                          onPressed: posProvider.cart.isNotEmpty
                              ? () => _showCartDialog(context, posProvider)
                              : null,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: Consumer<PosProviderV2>(
        builder: (context, posProvider, child) {
          // V2: No loading state - local DB is instant

          if (posProvider.errorMessage != null) {
            return Center(child: Text(posProvider.errorMessage!));
          }

          final products = posProvider.availableProducts;

          // Filtered list according to search query (case-insensitive substring match)
          final displayedProducts = _searchQuery.isEmpty
              ? products
              : posProvider.searchProducts(_searchQuery);

          return Column(
            children: [
              // Search bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    hintText: 'Search products',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _searchDebounce?.cancel();
                              setState(() => _searchQuery = '');
                            },
                          ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    // Debounce updates to reduce rebuilds while user types
                    _searchDebounce?.cancel();
                    _searchDebounce =
                        Timer(const Duration(milliseconds: 300), () {
                      final q = v.trim().toLowerCase();
                      setState(() => _searchQuery = q);
                    });
                  },
                ),
              ),

              if (displayedProducts.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('No products available. Check your inventory.'),
                  ),
                )
              else
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.1, // increased height (was 1.5)
                    ),
                    itemCount: displayedProducts.length,
                    itemBuilder: (context, index) {
                      final product = displayedProducts[index];
                      return ProductCard(
                        product: product,
                        onAdd: () => posProvider.addToCart(product, 1),
                      );
                    },
                  ),
                ),

              Container(
                padding: const EdgeInsets.all(16.0),
                color: Theme.of(context).colorScheme.surface,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total: \$${posProvider.total.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryAction),
                    ),
                    PrimaryButton(
                      onPressed: posProvider.cart.isNotEmpty
                          ? () => _processSale(context, posProvider)
                          : null,
                      child: const Text('Checkout'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: const AppBottomNav(currentRoute: '/pos'),
    );
  }

  void _showCartDialog(BuildContext mainContext, PosProviderV2 posProvider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Consumer<PosProviderV2>(
          builder: (context, provider, child) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Shopping Cart',
                    style: TextStyle(
                      color: AppColors.primaryBrand,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Total: \$${provider.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryAction),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: provider.cart.isEmpty
                    ? const Text('Your cart is empty')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: provider.cart.length,
                        itemBuilder: (context, index) {
                          final item = provider.cart[index];
                          final subtotal = item.lineTotal;

                          return ListTile(
                            title: Text(item.productName),
                            subtitle: Text(
                                'Qty: ${item.quantity} × \$${item.unitPrice.toStringAsFixed(2)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove),
                                  onPressed: () {
                                    provider.updateQuantity(
                                        item.productId, item.quantity - 1);
                                  },
                                ),
                                Text('${item.quantity}'),
                                IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: () {
                                    provider.updateQuantity(
                                        item.productId, item.quantity + 1);
                                  },
                                ),
                                Text('\$${subtotal.toStringAsFixed(2)}'),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Continue Shopping'),
                ),
                PrimaryButton(
                  onPressed: provider.cart.isNotEmpty
                      ? () {
                          Navigator.of(context).pop();
                          _processSale(mainContext, posProvider);
                        }
                      : null,
                  child: const Text('Checkout'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _processSale(BuildContext context, PosProviderV2 posProvider) async {
    // Show payment method selection dialog
    final paymentMethod = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text(
            'Select Payment Method',
            style: TextStyle(
              color: AppColors.primaryBrand,
              fontWeight: FontWeight.bold,
            ),
          ),
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primaryBrand,
                  child:
                      Icon(Icons.attach_money, color: Colors.white, size: 18),
                ),
                title: const Text('Cash'),
                onTap: () => Navigator.of(context).pop('cash'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primaryBrand,
                  child: Icon(Icons.credit_card, color: Colors.white, size: 18),
                ),
                title: const Text('Card'),
                onTap: () => Navigator.of(context).pop('card'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primaryBrand,
                  child: Icon(Icons.qr_code, color: Colors.white, size: 18),
                ),
                title: const Text('Paynow'),
                onTap: () => Navigator.of(context).pop('paynow'),
              ),
            ],
          ),
        );
      },
    );

    if (paymentMethod == null) return; // User cancelled

    try {
      await posProvider.processSale(paymentMethod);

      // Trigger immediate sync after completing sale
      debugPrint('🔄 Sale completed locally, triggering immediate sync...');
      if (context.mounted) {
        context.read<SyncProvider>().sync();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Sale completed successfully!'),
            action: SnackBarAction(
              label: 'View Receipts',
              onPressed: () {
                Navigator.of(context).pushNamed('/sales_history');
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing sale: $e')),
        );
      }
    }
  }
}
