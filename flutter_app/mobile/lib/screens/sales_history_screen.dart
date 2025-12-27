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

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

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
          unawaited(storeProvider.initialize());
        }
      } catch (e) {
        debugPrint('SalesHistoryScreen: store init skipped: $e');
      }

      // Listen for store changes to reload sales history
      _storeProvider = storeProvider;
      _storeProvider?.addListener(_loadSalesHistory);

      await _loadSalesHistory();
    });
  }

  Future<void> _loadSalesHistory() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);
      final storeProvider = context.read<StoreProvider>();
      final storeId = storeProvider.currentStore?['id'] as int?;
      final sales = await _salesService.getSales(storeId: storeId);
      if (!mounted) return;
      setState(() {
        _sales = sales;
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
                    'Total: \$${sale['total_amount']?.toStringAsFixed(2) ?? '0.00'}'),
                Text('Payment: ${sale['payment_method'] ?? 'N/A'}'),
                Text('Date: ${_formatDate(sale['created_at'])}'),
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
