import 'package:flutter/material.dart';
import 'package:mobile/providers/inventory_provider_v2.dart';
import 'package:mobile/providers/sync_provider.dart';
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
import 'package:mobile/widgets/offline_indicator.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:mobile/db/app_database.dart' show UserRole;

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
      final syncProvider = Provider.of<SyncProvider>(context, listen: false);

      // Set up sync completion callback to reload stores
      syncProvider.onSyncComplete = () async {
        debugPrint(
            '📥 HomeScreen: Sync complete - reloading stores and user data');
        storeProvider.loadMyStores();
        storeProvider.loadStores();

        // Refresh current user data in case it was updated during sync
        await authProvider.refreshCurrentUser();
      };

      // Ensure stores are loaded (they may already be loaded from login)
      if (storeProvider.stores.isEmpty) {
        debugPrint('📥 HomeScreen: No stores loaded, initializing...');
        await storeProvider.loadStores();
      }

      if (authProvider.role == UserRole.superadmin ||
          authProvider.role == UserRole.admin) {
        context.read<AnalyticsProvider>().loadAnalytics();
      }

      // Initialize inventory provider for low stock alerts
      try {
        final inventoryProvider = context.read<InventoryProviderV2>();
        inventoryProvider.setAuthProvider(authProvider);
        inventoryProvider.setStoreProvider(storeProvider);
        // V2 uses streams - no manual load needed
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
          const OfflineStatusIcon(),
          if (role == UserRole.superadmin || role == UserRole.admin)
            const StoreQuickAction(),
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
            // Offline indicator banner
            const OfflineIndicator(),
            const SizedBox(height: 8),

            // All Stores banner (visible when no specific store selected)
            if (storeProvider.currentStore == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 12.0),
                child: AllStoresBanner(),
              ),

            // Welcome Section
            _buildWelcomeSection(authProvider),

            const SizedBox(height: 24),

            // Quick Actions
            _buildQuickActionsSection(role),

            const SizedBox(height: 24),

            // Summary Cards (for admin/superadmin)
            if (role == UserRole.superadmin || role == UserRole.admin)
              _buildSummarySection(),

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

  Widget _buildQuickActionsSection(UserRole? role) {
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
          lowStock = context.watch<InventoryProviderV2>().lowStockCount;
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

  List<Widget> _getQuickActions(UserRole? role) {
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
    if (role == UserRole.superadmin || role == UserRole.admin) {
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
    if (role == UserRole.admin || role == UserRole.superadmin) {
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
    if (role == UserRole.superadmin) {
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

  IconData _getRoleIcon(UserRole? role) {
    switch (role) {
      case UserRole.superadmin:
        return Icons.admin_panel_settings;
      case UserRole.admin:
        return Icons.business;
      case UserRole.cashier:
        return Icons.point_of_sale;
      default:
        return Icons.person;
    }
  }

  Color _getRoleColor(UserRole? role) {
    switch (role) {
      case UserRole.superadmin:
        return AppColors.secondaryAccent;
      case UserRole.admin:
        return AppColors.primaryBrand;
      case UserRole.cashier:
        return AppColors.primaryAction;
      default:
        return Colors.grey;
    }
  }

  String _getRoleDisplayName(UserRole? role) {
    switch (role) {
      case UserRole.superadmin:
        return 'Super Administrator';
      case UserRole.admin:
        return 'Store Administrator';
      case UserRole.cashier:
        return 'Cashier';
      default:
        return 'User';
    }
  }

  String _getWelcomeMessage(UserRole? role) {
    switch (role) {
      case UserRole.superadmin:
        return 'Manage stores, users, and oversee all operations.';
      case UserRole.admin:
        return 'Manage your store inventory and staff.';
      case UserRole.cashier:
        return 'Process sales and serve customers.';
      default:
        return 'Welcome to the POS system.';
    }
  }
}
