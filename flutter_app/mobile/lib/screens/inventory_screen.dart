import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile/utils/smooth_page_route.dart';
// import 'package:flutter/foundation.dart';
import 'package:mobile/widgets/low_stock_panel.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/inventory_provider_v2.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/sync_provider.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:mobile/widgets/store_badge.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:mobile/db/app_database.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  // Bulk selection state for products
  final Set<int> _selectedProductIds = {};
  bool _isBulkActionLoading = false;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  // V2: No need for manual loading - streams handle it automatically

  @override
  void initState() {
    super.initState();
    // Initialize providers when screen loads (V2: streams handle data loading)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final inventoryProvider = context.read<InventoryProviderV2>();
      final authProvider = context.read<AuthProvider>();
      final storeProvider = context.read<StoreProvider>();

      // Ensure store provider is initialized
      try {
        if (!storeProvider.isInitialized) {
          unawaited(storeProvider.initialize());
        }
      } catch (e) {
        debugPrint('InventoryScreen: store init skipped: $e');
      }

      // Set up providers (V2: this starts the streams)
      inventoryProvider.setAuthProvider(authProvider);
      inventoryProvider.setStoreProvider(storeProvider);

      // If a non-admin is on All Stores, fallback to first myStore when available
      if (storeProvider.currentStore == null &&
          authProvider.role != UserRole.superadmin &&
          authProvider.role != UserRole.admin) {
        if (storeProvider.myStores.isNotEmpty) {
          await storeProvider.switchStore(storeProvider.myStores.first);
        }
      }

      // V2: No manual loading needed - streams auto-populate products
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _confirmBulkToggleProductStatus(bool activate) async {
    final inventoryProvider = context.read<InventoryProviderV2>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Product Status'),
        content: Text(
            'Are you sure you want to ${activate ? 'activate' : 'deactivate'} ${_selectedProductIds.length} selected products?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _isBulkActionLoading = true);
    try {
      for (final id in _selectedProductIds.toList()) {
        await inventoryProvider.updateProductStatus(id, activate);
      }
      // Trigger sync after bulk update
      if (context.mounted) {
        context.read<SyncProvider>().sync();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bulk status update completed')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error performing bulk update: $e')));
      }
    } finally {
      setState(() {
        _isBulkActionLoading = false;
        _selectedProductIds.clear();
      });
    }
  }

  Future<void> _confirmBulkDeleteProducts() async {
    final inventoryProvider = context.read<InventoryProviderV2>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Products'),
        content: Text(
            'Are you sure you want to permanently delete ${_selectedProductIds.length} selected products? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;
    setState(() => _isBulkActionLoading = true);
    try {
      for (final id in _selectedProductIds.toList()) {
        await inventoryProvider.deleteProduct(id);
      }
      // Trigger sync after bulk delete
      if (context.mounted) {
        context.read<SyncProvider>().sync();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selected products deleted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting products: $e')));
      }
    } finally {
      setState(() {
        _isBulkActionLoading = false;
        _selectedProductIds.clear();
      });
    }
  }

  Future<void> _confirmDeleteProduct(Product product) async {
    final inventoryProvider = context.read<InventoryProviderV2>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text(
            'Are you sure you want to permanently delete "${product.name}"? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await inventoryProvider.deleteProduct(product.id);
      // Trigger sync after delete
      if (context.mounted) {
        context.read<SyncProvider>().sync();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Product "${product.name}" deleted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting product: $e')));
      }
    }
  }

  void _clearProductSelection() {
    setState(() => _selectedProductIds.clear());
  }

  /// Converts a Product object to Map and navigates to edit product screen
  void _openProductFromAlert(Product alert) {
    // Use the new getter that provides the product as a map
    final productMap = {
      'id': alert.id,
      'name': alert.name,
      'description': alert.description,
      'sku': alert.sku,
      'price': alert.price,
      'stock_quantity': alert.stockQuantity,
      'is_active': alert.isActive,
      'store_id': alert.storeId,
    };

    // Close dialog then navigate to edit product screen
    Navigator.of(context).pop();
    Future.microtask(
        () => context.pushNamedSmooth('/edit_product', arguments: productMap));
  }

  /// Return display name for a low-stock Product alert
  String _displayNameForAlert(Product alert) {
    return alert.name;
  }

  @override
  Widget build(BuildContext context) {
    final inventoryProvider = Provider.of<InventoryProviderV2>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.role != UserRole.superadmin &&
        authProvider.role != UserRole.admin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
            child: Text('You do not have permission to access this screen.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
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
                Wrap(
                  spacing: 1.0, // Reduced spacing between buttons
                  children: [
                    if (context.watch<AuthProvider>().role ==
                            UserRole.superadmin ||
                        context.watch<AuthProvider>().role == UserRole.admin)
                      const StoreQuickAction(),
                    IconButton(
                      icon: const Icon(Icons.visibility, color: Colors.white),
                      tooltip: inventoryProvider.showInactiveProducts
                          ? 'Hide inactive'
                          : 'Show inactive',
                      onPressed: () =>
                          inventoryProvider.toggleShowInactiveProducts(),
                    ),
                    // V2: No refresh button needed - streams auto-update
                    // IconButton(
                    //   icon: const Icon(Icons.refresh, color: Colors.white),
                    //   onPressed: _loadProducts,
                    // ),
                    // IconButton(
                    //   icon: const Icon(Icons.cleaning_services,
                    //       color: Colors.white),
                    //   tooltip: 'Clean up orphaned products',
                    //   onPressed: () async {
                    //     final confirmed = await showDialog<bool>(
                    //       context: context,
                    //       builder: (context) => AlertDialog(
                    //         title: const Text('Clean Up Orphaned Products'),
                    //         content: const Text(
                    //             'This will remove products that exist only locally and have never been synced to the server. '
                    //             'This action cannot be undone. Continue?'),
                    //         actions: [
                    //           TextButton(
                    //             onPressed: () =>
                    //                 Navigator.of(context).pop(false),
                    //             child: const Text('Cancel'),
                    //           ),
                    //           TextButton(
                    //             onPressed: () =>
                    //                 Navigator.of(context).pop(true),
                    //             child: const Text('Clean Up'),
                    //           ),
                    //         ],
                    //       ),
                    //     );

                    //     if (confirmed == true) {
                    //       final removedCount =
                    //           await inventoryProvider.cleanupOrphanedProducts();
                    //       if (mounted) {
                    //         ScaffoldMessenger.of(context).showSnackBar(
                    //           SnackBar(
                    //               content: Text(
                    //                   'Removed $removedCount orphaned products')),
                    //         );
                    //       }
                    //     }
                    //   },
                    // ),
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.white),
                      onPressed: () {
                        Navigator.of(context).pushNamed('/add_product');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      // V2: isLoading always false (local DB is instant), no need for loading spinner
      body: inventoryProvider.errorMessage != null
          ? Center(child: Text(inventoryProvider.errorMessage!))
          : inventoryProvider.products.isEmpty
              ? const Center(child: Text('No products found'))
              : Column(
                  children: [
                    // Bulk action bar (visible when there are selections)
                    if (_selectedProductIds.isNotEmpty)
                      Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: LayoutBuilder(builder: (context, constraints) {
                          return Wrap(
                            alignment: WrapAlignment.start,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth * 0.22),
                                child: Text(
                                  '${_selectedProductIds.length} selected',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth * 0.78),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: _isBulkActionLoading
                                            ? const CircularProgressIndicator(
                                                strokeWidth: 2)
                                            : const SizedBox.shrink(),
                                      ),
                                      const SizedBox(width: 4),

                                      // Select-all
                                      Builder(builder: (context) {
                                        final visibleIds = inventoryProvider
                                            .products
                                            .map((p) => p.id)
                                            .toList();
                                        final allSelected =
                                            visibleIds.isNotEmpty &&
                                                visibleIds.every((id) =>
                                                    _selectedProductIds
                                                        .contains(id));

                                        return IconButton(
                                          tooltip: allSelected
                                              ? 'Clear selection'
                                              : 'Select all',
                                          onPressed: _isBulkActionLoading
                                              ? null
                                              : () {
                                                  setState(() {
                                                    if (allSelected) {
                                                      _selectedProductIds
                                                          .clear();
                                                    } else {
                                                      _selectedProductIds
                                                          .addAll(visibleIds);
                                                    }
                                                  });
                                                },
                                          padding: const EdgeInsets.all(6),
                                          icon: Icon(allSelected
                                              ? Icons.check_box
                                              : Icons.select_all),
                                        );
                                      }),
                                      const SizedBox(width: 4),

                                      // Bulk toggle activation
                                      Builder(builder: (context) {
                                        final selectedProducts =
                                            inventoryProvider.products
                                                .where((p) =>
                                                    _selectedProductIds
                                                        .contains(p.id))
                                                .toList();
                                        final hasInactive = selectedProducts
                                            .any((p) => !p.isActive);
                                        final hasActive = selectedProducts
                                            .any((p) => p.isActive);

                                        IconData toggleIcon;
                                        Color? toggleColor;
                                        String tooltip;

                                        if (hasActive && hasInactive) {
                                          toggleIcon = Icons.sync;
                                          toggleColor = Colors.amber;
                                          tooltip = 'Toggle activation (mixed)';
                                        } else if (hasInactive) {
                                          toggleIcon = Icons.toggle_on;
                                          toggleColor = Colors.green;
                                          tooltip = 'Activate selected';
                                        } else {
                                          toggleIcon = Icons.toggle_off;
                                          toggleColor = Colors.grey;
                                          tooltip = 'Deactivate selected';
                                        }

                                        final targetActivate = hasInactive;

                                        return AnimatedSwitcher(
                                          duration:
                                              const Duration(milliseconds: 220),
                                          transitionBuilder:
                                              (child, animation) =>
                                                  ScaleTransition(
                                                      scale: animation,
                                                      child: FadeTransition(
                                                          opacity: animation,
                                                          child: child)),
                                          child: IconButton(
                                            key: ValueKey<int>(
                                                toggleIcon.codePoint),
                                            tooltip: tooltip,
                                            onPressed: _isBulkActionLoading
                                                ? null
                                                : () =>
                                                    _confirmBulkToggleProductStatus(
                                                        targetActivate),
                                            padding: const EdgeInsets.all(6),
                                            icon: Icon(toggleIcon,
                                                color: toggleColor),
                                          ),
                                        );
                                      }),
                                      const SizedBox(width: 4),

                                      IconButton(
                                        tooltip: 'Delete',
                                        onPressed: _isBulkActionLoading
                                            ? null
                                            : () =>
                                                _confirmBulkDeleteProducts(),
                                        padding: const EdgeInsets.all(6),
                                        icon: const Icon(Icons.delete_forever),
                                        color: _isBulkActionLoading
                                            ? null
                                            : Colors.red,
                                      ),
                                      const SizedBox(width: 4),

                                      IconButton(
                                        tooltip: 'Clear',
                                        onPressed: _isBulkActionLoading
                                            ? null
                                            : _clearProductSelection,
                                        padding: const EdgeInsets.all(6),
                                        icon: const Icon(Icons.clear),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),

                    // Search bar for quick product lookup
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
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
                          _searchDebounce?.cancel();
                          _searchDebounce =
                              Timer(const Duration(milliseconds: 300), () {
                            final q = v.trim().toLowerCase();
                            setState(() => _searchQuery = q);
                          });
                        },
                      ),
                    ),

                    Expanded(
                      // V2: Streams handle reactivity, no need for RefreshIndicator
                      child: Builder(builder: (context) {
                        final displayedProducts = _searchQuery.isEmpty
                            ? inventoryProvider.products
                            : inventoryProvider.products
                                .where((p) =>
                                    p.name.toLowerCase().contains(_searchQuery))
                                .toList();

                        return ListView.builder(
                          itemCount: displayedProducts.length + 1,
                          itemBuilder: (context, index) {
                            // index 0 reserved for LowStockPanel
                            if (index == 0) {
                              return Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: LowStockPanel(
                                  count: inventoryProvider.lowStockCount,
                                  criticalCount:
                                      inventoryProvider.criticalLowStockCount,
                                  onView: () {
                                    showDialog(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                              title: const Text(
                                                  'Low stock alerts',
                                                  style: TextStyle(
                                                      color: AppColors
                                                          .primaryBrand)),
                                              content: SizedBox(
                                                width: double.maxFinite,
                                                child: ListView(
                                                  shrinkWrap: true,
                                                  children: inventoryProvider
                                                      .lowStockAlerts
                                                      .map((a) => ListTile(
                                                            title: Text(
                                                                _displayNameForAlert(
                                                                    a)),
                                                            subtitle: Text(
                                                                'Stock: ${a.stockQuantity}'),
                                                            onTap: () =>
                                                                _openProductFromAlert(
                                                                    a),
                                                          ))
                                                      .toList(),
                                                ),
                                              ),
                                            ));
                                  },
                                ),
                              );
                            }

                            final product = displayedProducts[index - 1];
                            final id = product.id;
                            final isSelected = _selectedProductIds.contains(id);
                            final isActive = product.isActive;

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: InkWell(
                                // Long-press toggles selection for this product (adds or removes it)
                                onLongPress: () {
                                  setState(() {
                                    if (_selectedProductIds.contains(id)) {
                                      _selectedProductIds.remove(id);
                                    } else {
                                      _selectedProductIds.add(id);
                                    }
                                  });
                                },
                                onTap: () {
                                  if (_selectedProductIds.isNotEmpty) {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedProductIds.remove(id);
                                      } else {
                                        _selectedProductIds.add(id);
                                      }
                                    });
                                    return;
                                  }
                                  // Future: open product details/edit
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      // Left: selection control / avatar
                                      SizedBox(
                                        width: 25,
                                        height: 25,
                                        child: _selectedProductIds.isEmpty
                                            ? CircleAvatar(
                                                backgroundColor:
                                                    const Color.fromARGB(
                                                        131, 31, 60, 97),
                                                foregroundColor: Colors.white,
                                                child: Text(product.name[0]),
                                              )
                                            : Checkbox(
                                                value: isSelected,
                                                onChanged: (v) => setState(() {
                                                  if (v == true) {
                                                    _selectedProductIds.add(id);
                                                  } else {
                                                    _selectedProductIds
                                                        .remove(id);
                                                  }
                                                }),
                                              ),
                                      ),

                                      const SizedBox(width: 8),

                                      // Middle: product details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              product.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyLarge
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Stock: ${product.stockQuantity}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                      color: inventoryProvider
                                                              .lowStockAlerts
                                                              .any((a) =>
                                                                  a.id ==
                                                                  product.id)
                                                          ? Colors.red
                                                          : AppColors
                                                              .primaryAction),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Spacer to push trailing controls to the far right and create more middle space
                                      const SizedBox(width: 24),

                                      // Right: compact controls (minimal width so middle can expand)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 35,
                                            child: FittedBox(
                                              alignment: Alignment.centerRight,
                                              child: Text(
                                                '\$${product.price.toStringAsFixed(2)}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4.0, vertical: 6.0),
                                            iconSize: 18,
                                            icon: Icon(
                                              isActive
                                                  ? Icons.visibility_off
                                                  : Icons.visibility,
                                            ),
                                            tooltip: isActive
                                                ? 'Deactivate'
                                                : 'Activate',
                                            onPressed: _isBulkActionLoading
                                                ? null
                                                : () async {
                                                    try {
                                                      await inventoryProvider
                                                          .updateProductStatus(
                                                              product.id,
                                                              !isActive);
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(SnackBar(
                                                                content: Text(
                                                                    'Product ${isActive ? 'deactivated' : 'activated'} successfully!')));
                                                      }
                                                    } catch (e) {
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(SnackBar(
                                                                content: Text(
                                                                    'Error updating status: $e')));
                                                      }
                                                    }
                                                  },
                                          ),
                                          PopupMenuButton<String>(
                                            icon: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 4.0),
                                              child: Icon(Icons.more_vert,
                                                  size: 18),
                                            ),
                                            onSelected: (value) {
                                              if (value == 'edit') {
                                                final productMap = {
                                                  'id': product.id,
                                                  'name': product.name,
                                                  'description':
                                                      product.description,
                                                  'sku': product.sku,
                                                  'price': product.price,
                                                  'stock_quantity':
                                                      product.stockQuantity,
                                                  'is_active': product.isActive,
                                                  'store_id': product.storeId,
                                                };
                                                context.pushNamedSmooth(
                                                    '/edit_product',
                                                    arguments: productMap);
                                              } else if (value == 'delete') {
                                                _confirmDeleteProduct(product);
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: Text('Edit'),
                                              ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      }),
                    ),
                  ],
                ),
      bottomNavigationBar: const AppBottomNav(currentRoute: '/inventory'),
    );
  }
}
