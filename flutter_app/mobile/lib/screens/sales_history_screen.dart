import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/widgets/store_badge.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:mobile/data/repositories/sale_repository_v2.dart';
import 'package:mobile/db/app_database.dart';

class SalesHistoryScreen extends StatefulWidget {
  final SaleRepository? saleRepository;
  const SalesHistoryScreen({super.key, this.saleRepository});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  List<Map<String, dynamic>> _sales = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Keep a reference to the store provider so we can remove listeners on dispose
  StoreProvider? _storeProvider;

  @override
  void dispose() {
    // Remove listener to avoid setState being called after widget is disposed
    _storeProvider?.removeListener(_loadSalesHistory);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Ensure store provider is initialized and then load sales
      final storeProvider = context.read<StoreProvider>();
      try {
        if (!storeProvider.isInitialized) {
          await storeProvider.initialize();
        }
      } catch (e) {
        debugPrint('SalesHistoryScreen: store init failed: $e');
      }

      // Listen for store changes to reload sales history
      _storeProvider = storeProvider;
      _storeProvider?.addListener(_loadSalesHistory);

      // Ensure non-admin users are not left on an implicit All Stores view
      final authProvider = context.read<AuthProvider>();
      if (storeProvider.currentStore == null &&
          authProvider.role != UserRole.superadmin &&
          authProvider.role != UserRole.admin) {
        debugPrint(
            'SalesHistoryScreen: cashier with no current store, waiting for myStores...');
        // Await myStores to be loaded
        await storeProvider.loadMyStores();
        // Try to fallback to the user's assigned store if available
        if (storeProvider.myStores.isNotEmpty) {
          debugPrint(
              'SalesHistoryScreen: switching to first myStore: ${storeProvider.myStores.first}');
          await storeProvider.switchStore(storeProvider.myStores.first);
        } else {
          debugPrint('SalesHistoryScreen: cashier has no assigned stores!');
        }
      }

      debugPrint(
          'SalesHistoryScreen: loading sales with currentStore=${storeProvider.currentStore}');
      await _loadSalesHistory();
    });
  }

  Future<void> _loadSalesHistory() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      final List<Map<String, dynamic>> allSales = [];

      // Get current store context
      final storeProvider = context.read<StoreProvider>();
      final rawIdValue = storeProvider.currentStore == null
          ? null
          : storeProvider.currentStore?['id'];
      final int? rawId = rawIdValue is int
          ? rawIdValue
          : int.tryParse(rawIdValue?.toString() ?? '');
      final int? storeId = (rawId == 0) ? null : rawId;

      debugPrint('SalesHistoryScreen._loadSalesHistory: storeId=$storeId');

      // Load sales from V2 repository (fully offline)
      final saleRepository =
          widget.saleRepository ?? context.read<SaleRepository>();
      try {
        final sales = await saleRepository.getAllSales(storeId: storeId);
        debugPrint(
            'SalesHistoryScreen: loaded ${sales.length} sales for storeId=$storeId');

        // Convert Sale entities to display format
        for (final sale in sales) {
          allSales.add({
            'id': sale.serverId ?? sale.id, // Prefer server_id for display
            'local_id': sale.id, // Keep local id for reference
            'server_id': sale.serverId, // Track sync status
            'total': sale.totalAmount,
            'payment_method': sale.paymentMethod,
            'created_at': sale.createdAt.toIso8601String(),
            'transaction_number': sale.transactionNumber,
            'is_offline':
                sale.serverId == null, // Only truly offline if not synced
            'is_synced': sale.serverId != null,
            'store_id': sale.storeId,
          });
        }
      } catch (e) {
        debugPrint('Failed to load sales: $e');
        _errorMessage = 'Failed to load sales: $e';
      }

      if (!mounted) return;
      setState(() {
        _sales = allSales;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load sales history: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeProvider = context.watch<StoreProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales History'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: StoreIndicator(
            store: storeProvider.currentStore,
          ),
        ),
        actions: [
          // Allow admins to quick-switch stores here
          if (context.read<AuthProvider>().role == UserRole.superadmin ||
              context.read<AuthProvider>().role == UserRole.admin)
            const StoreQuickAction(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSalesHistory,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: const AppBottomNav(currentRoute: '/sales_history'),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSalesHistory,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_sales.isEmpty) {
      return const Center(
        child: Text('No sales found. Make your first sale!'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _sales.length,
      itemBuilder: (context, index) {
        final sale = _sales[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8.0),
          child: ListTile(
            title: Text('Sale #${sale['id']}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Total: \$${sale['total_amount']?.toStringAsFixed(2) ?? sale['total']?.toStringAsFixed(2) ?? '0.00'}'),
                Text('Payment: ${sale['payment_method'] ?? 'N/A'}'),
                Text('Date: ${_formatDate(sale['created_at'])}'),
                if (sale['is_offline'] == true) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[300]!),
                    ),
                    child: Text(
                      'Offline',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Use local_id for lookups (route expects local DB id), display id may be server id
              final localId = sale['local_id'] as int? ?? sale['id'] as int?;
              debugPrint(
                  'SalesHistoryScreen: opening receipt for local_id=$localId (display id=${sale['id']})');
              if (localId != null) {
                Navigator.of(context).pushNamed('/receipt', arguments: localId);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid sale data')),
                );
              }
            },
          ),
        );
      },
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }
}
