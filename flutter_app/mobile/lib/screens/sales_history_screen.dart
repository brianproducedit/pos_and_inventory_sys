import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/services/sales_service.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/widgets/store_badge.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:mobile/data/repositories/transaction_repository.dart';

class SalesHistoryScreen extends StatefulWidget {
  final SalesService? salesService;
  final TransactionRepository? transactionRepository;
  const SalesHistoryScreen(
      {super.key, this.salesService, this.transactionRepository});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final SalesService _salesService = SalesService();
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
          authProvider.role != 'superadmin' &&
          authProvider.role != 'admin') {
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

      // Track server_ids from offline transactions for de-duplication with online sales
      final Set<int> offlineServerIds = {};

      // First try to load offline transactions (filtered by store)
      if (widget.transactionRepository != null) {
        try {
          final offlineTransactions = await widget.transactionRepository!
              .getAllTransactions(storeId: storeId);
          debugPrint(
              'SalesHistoryScreen: loaded ${offlineTransactions.length} offline transactions for storeId=$storeId');
          // Convert offline transactions to sales format
          for (final tx in offlineTransactions) {
            // Track server_id for de-duplication (if synced)
            if (tx.serverId != null) {
              offlineServerIds.add(tx.serverId!);
            }

            allSales.add({
              'id': tx.serverId ?? tx.id, // Prefer server_id for display
              'local_id': tx.id, // Keep local id for reference
              'server_id': tx.serverId, // Track sync status
              'total': tx.totalAmount,
              'payment_method': tx.paymentMethod,
              'created_at': tx.createdAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(tx.createdAt!)
                      .toIso8601String()
                  : DateTime.now().toIso8601String(),
              'transaction_number':
                  tx.serverId != null ? 'TXN-${tx.serverId}' : 'LOCAL-${tx.id}',
              'is_offline':
                  tx.serverId == null, // Only truly offline if not synced
              'is_synced': tx.serverId != null,
              'store_id': tx.storeId,
            });
          }
        } catch (e) {
          debugPrint('Failed to load offline transactions: $e');
        }
      }

      // Then try to load online sales
      try {
        final service = widget.salesService ?? SalesService();
        debugPrint(
            'SalesHistoryScreen: fetching online sales for storeId=$storeId');
        final onlineSales = await service.getSales(storeId: storeId);
        debugPrint(
            'SalesHistoryScreen: loaded ${onlineSales.length} online sales');

        // Add online sales, avoiding duplicates using server_id
        for (final sale in onlineSales) {
          final saleId = sale['id'] as int?;
          // Skip if we already have this sale from offline storage (synced transaction)
          if (saleId != null && offlineServerIds.contains(saleId)) {
            debugPrint(
                'SalesHistoryScreen: skipping duplicate sale id=$saleId (already in offline)');
            continue;
          }
          allSales.add({...sale, 'is_offline': false, 'is_synced': true});
        }
      } catch (e) {
        debugPrint('Failed to load online sales: $e');
        // Continue with offline transactions only
      }

      // Sort by creation date (newest first)
      allSales.sort((a, b) => DateTime.parse(b['created_at'])
          .compareTo(DateTime.parse(a['created_at'])));

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
          if (context.read<AuthProvider>().role == 'superadmin' ||
              context.read<AuthProvider>().role == 'admin')
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
              final saleId = sale['id'];
              if (saleId != null) {
                Navigator.of(context).pushNamed('/receipt', arguments: saleId);
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
