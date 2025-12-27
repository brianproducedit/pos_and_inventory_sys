import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:mobile/providers/inventory_provider.dart';
import 'package:mobile/services/time_service.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/widgets/store_badge.dart';
import 'package:mobile/widgets/all_stores_banner.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:mobile/widgets/metric_card.dart';
import 'package:mobile/theme/tokens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Load analytics data for summary cards
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final storeProvider = Provider.of<StoreProvider>(context, listen: false);

      if (authProvider.role == 'superadmin' || authProvider.role == 'admin') {
        context.read<AnalyticsProvider>().loadAnalytics();
      }

      // Ensure inventory provider has up-to-date alerts for quick summary card
      try {
        final inventoryProvider = context.read<InventoryProvider>();
        inventoryProvider.setAuthProvider(authProvider);
        inventoryProvider.setStoreProvider(storeProvider);
        unawaited(inventoryProvider.loadLowStockAlerts());
      } catch (e) {
        debugPrint('InventoryProvider not present on HomeScreen init: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final storeProvider = Provider.of<StoreProvider>(context);
    final role = authProvider.role;

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS & Inventory System'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Current Store Indicator
                Expanded(
                  child: StoreIndicator(
                    store: storeProvider.currentStore,
                  ),
                ),
                // Note: store switching is available via the quick action in the AppBar actions
                // (keeps UI consistent and avoids duplicate switch controls)
              ],
            ),
          ),
        ),
        actions: [
          if (role == 'superadmin' || role == 'admin') const StoreQuickAction(),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              authProvider.logout();
              Navigator.of(context).pushReplacementNamed('/login');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // All Stores banner (visible when no specific store selected)
            if (storeProvider.currentStore == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: const AllStoresBanner(),
              ),

            // Welcome Section
            _buildWelcomeSection(authProvider),

            const SizedBox(height: 24),

            // Quick Actions
            _buildQuickActionsSection(role),

            const SizedBox(height: 24),

            // Summary Cards (for admin/superadmin)
            if (role == 'superadmin' || role == 'admin') _buildSummarySection(),

            const SizedBox(height: 24),

            // Recent Activity (placeholder for now)
            _buildRecentActivitySection(),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentRoute: '/home'),
    );
  }

  Widget _buildWelcomeSection(AuthProvider authProvider) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getRoleIcon(authProvider.role),
                  size: 32,
                  color: _getRoleColor(authProvider.role),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back, ${authProvider.username ?? 'User'}!',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _getRoleDisplayName(authProvider.role),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _getWelcomeMessage(authProvider.role),
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsSection(String? role) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: _getQuickActions(role),
        ),
      ],
    );
  }

  Widget _buildSummarySection() {
    return Consumer<AnalyticsProvider>(
      builder: (context, analyticsProvider, child) {
        if (analyticsProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final salesData = analyticsProvider.salesData;

        // Safely read inventory counts (may not be present in some tests)
        int lowStock = 0;
        try {
          lowStock = context.watch<InventoryProvider>().lowStockCount;
        } catch (_) {
          lowStock = 0;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Today\'s Summary',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    title: 'Total Sales',
                    value: '${salesData['total_sales'] ?? 0}',
                    icon: Icons.shopping_cart,
                    color: AppColors.primaryBrand,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: MetricCard(
                    title: 'Revenue',
                    value:
                        '\$${(salesData['total_revenue'] ?? 0).toStringAsFixed(2)}',
                    icon: Icons.attach_money,
                    color: AppColors.primaryAction,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    title: 'Low Stock',
                    value: '$lowStock',
                    icon: Icons.warning,
                    color: lowStock == 0
                        ? AppColors.primaryAction
                        : AppColors.warning,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: MetricCard(
                    title: 'Avg Sale',
                    value:
                        '\$${(salesData['average_sale'] ?? 0).toStringAsFixed(2)}',
                    icon: Icons.trending_up,
                    color: AppColors.secondaryAccent,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecentActivitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'System is ready for operations',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Last updated: ${TimeService.instance.formatNow()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildSummaryCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _getQuickActions(String? role) {
    List<Widget> actions = [];

    // POS action (available to all roles)
    actions.add(
      _buildQuickActionCard(
        'New Sale',
        Icons.point_of_sale,
        Colors.green,
        () => Navigator.of(context).pushReplacementNamed('/pos'),
      ),
    );

    // Sales History action (available to all roles)
    actions.add(
      _buildQuickActionCard(
        'Sales History',
        Icons.receipt_long,
        Colors.teal,
        () => Navigator.of(context).pushNamed('/sales_history'),
      ),
    );

    // Settings action (available to all roles)
    actions.add(
      _buildQuickActionCard(
        'Settings',
        Icons.settings,
        Colors.grey,
        () => Navigator.of(context).pushNamed('/settings'),
      ),
    );

    // Inventory actions (admin/superadmin only)
    if (role == 'superadmin' || role == 'admin') {
      actions.add(
        _buildQuickActionCard(
          'Add Product',
          Icons.add_box,
          Colors.blue,
          () => Navigator.of(context).pushNamed('/add_product'),
        ),
      );

      actions.add(
        _buildQuickActionCard(
          'View Inventory',
          Icons.inventory,
          Colors.orange,
          () => Navigator.of(context).pushReplacementNamed('/inventory'),
        ),
      );

      actions.add(
        _buildQuickActionCard(
          'Analytics',
          Icons.analytics,
          Colors.purple,
          () => Navigator.of(context).pushReplacementNamed('/analytics'),
        ),
      );

      actions.add(
        _buildQuickActionCard(
          'Audit Logs',
          Icons.history,
          Colors.brown,
          () => Navigator.of(context).pushReplacementNamed('/audit_logs'),
        ),
      );
    }

    // Admin and Superadmin specific actions
    if (role == 'admin' || role == 'superadmin') {
      actions.add(
        _buildQuickActionCard(
          'Cashier Management',
          Icons.people,
          Colors.teal,
          () => Navigator.of(context).pushNamed('/cashier_management'),
        ),
      );
    }

    // Superadmin specific actions
    if (role == 'superadmin') {
      actions.add(
        _buildQuickActionCard(
          'Store Management',
          Icons.store,
          Colors.indigo,
          () => Navigator.of(context).pushNamed('/store_management'),
        ),
      );

      actions.add(
        _buildQuickActionCard(
          'Admin Management',
          Icons.admin_panel_settings,
          Colors.red,
          () => Navigator.of(context).pushNamed('/admin_management'),
        ),
      );
    }

    return actions;
  }

  Widget _buildQuickActionCard(
      String title, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getRoleIcon(String? role) {
    switch (role) {
      case 'superadmin':
        return Icons.admin_panel_settings;
      case 'admin':
        return Icons.business;
      case 'cashier':
        return Icons.point_of_sale;
      default:
        return Icons.person;
    }
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'superadmin':
        return AppColors.secondaryAccent;
      case 'admin':
        return AppColors.primaryBrand;
      case 'cashier':
        return AppColors.primaryAction;
      default:
        return Colors.grey;
    }
  }

  String _getRoleDisplayName(String? role) {
    switch (role) {
      case 'superadmin':
        return 'Super Administrator';
      case 'admin':
        return 'Store Administrator';
      case 'cashier':
        return 'Cashier';
      default:
        return 'User';
    }
  }

  String _getWelcomeMessage(String? role) {
    switch (role) {
      case 'superadmin':
        return 'Manage stores, users, and oversee all operations.';
      case 'admin':
        return 'Manage your store inventory and staff.';
      case 'cashier':
        return 'Process sales and serve customers.';
      default:
        return 'Welcome to the POS system.';
    }
  }
}
