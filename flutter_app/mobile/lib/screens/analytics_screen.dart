import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile/widgets/metric_card.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/inventory_provider_v2.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:mobile/widgets/store_badge.dart';
import 'package:mobile/db/app_database.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  bool _isSuperAdmin = false;
  bool _isInitialized = false;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    // Initialize tab controller immediately
    _tabController = TabController(length: 3, vsync: this);
    // Determine user role for dynamic UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAnalytics();
    });
  }

  Future<void> _initializeAnalytics() async {
    // Prevent multiple concurrent initializations
    if (_isInitializing || _isInitialized) return;
    _isInitializing = true;

    final analyticsProvider = context.read<AnalyticsProvider>();
    final authProvider = context.read<AuthProvider>();
    final storeProvider = context.read<StoreProvider>();

    try {
      // Ensure store provider is initialized so an explicit All Stores selection is restored
      try {
        if (!storeProvider.isInitialized) {
          // Start initialize in the background to avoid creating timeout timers
          unawaited(storeProvider.initialize());
        }
      } catch (e) {
        debugPrint('AnalyticsScreen: store init skipped: $e');
      }

      // Set provider references for filtering
      analyticsProvider.setAuthProvider(authProvider);
      analyticsProvider.setStoreProvider(storeProvider);

      // Initialize inventory provider if available (some tests don't include it)
      try {
        final inventoryProvider = context.read<InventoryProviderV2>();
        inventoryProvider.setAuthProvider(authProvider);
        inventoryProvider.setStoreProvider(storeProvider);
        // V2 uses streams - no manual load needed
      } catch (e) {
        debugPrint('InventoryProvider not present: $e');
      }

      // Determine user role for dynamic UI
      _isSuperAdmin = authProvider.role == UserRole.superadmin;

      // Update tab controller with correct length if needed
      final targetLength = _isSuperAdmin ? 4 : 3;
      if (_tabController != null && _tabController!.length != targetLength) {
        _tabController!.dispose();
        _tabController = TabController(length: targetLength, vsync: this);
      }

      // Load analytics filtered by current store with timeout
      await analyticsProvider.loadAnalyticsForCurrentStore().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('AnalyticsScreen: loadAnalyticsForCurrentStore timed out');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Analytics loading timed out')),
            );
          }
        },
      );

      // Mark as initialized to show the content
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isInitializing = false;
        });
      }
    } catch (e, st) {
      // Prevent initialization errors from crashing the UI; show a snackbar and
      // fall back to a minimal tab controller so the screen can render.
      debugPrint('AnalyticsScreen._initializeAnalytics failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to initialize analytics: ${e.toString()}')));
      }
      try {
        _isSuperAdmin = authProvider.role == UserRole.superadmin;
      } catch (_) {
        _isSuperAdmin = false;
      }
      // Ensure we have a valid tab controller
      _tabController ??=
          TabController(length: _isSuperAdmin ? 4 : 3, vsync: this);
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text('Analytics Dashboard'),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          // preferredSize: const Size.fromHeight(88),
          preferredSize: const Size.fromHeight(120),
          child: Column(
            children: [
              if (_isInitialized && _tabController != null)
                TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  tabs: _isSuperAdmin
                      ? const [
                          Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
                          Tab(text: 'Sales', icon: Icon(Icons.trending_up)),
                          Tab(text: 'Inventory', icon: Icon(Icons.inventory)),
                          Tab(text: 'Cross-Store', icon: Icon(Icons.store)),
                        ]
                      : const [
                          Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
                          Tab(text: 'Sales', icon: Icon(Icons.trending_up)),
                          Tab(text: 'Inventory', icon: Icon(Icons.inventory)),
                        ],
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                        child: StoreIndicator(
                            store:
                                context.watch<StoreProvider>().currentStore)),
                    if (context.watch<AuthProvider>().role ==
                            UserRole.superadmin ||
                        context.watch<AuthProvider>().role == UserRole.admin)
                      const StoreQuickAction(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isInitialized && _tabController != null
          ? TabBarView(
              controller: _tabController,
              children: _isSuperAdmin
                  ? [
                      _buildOverviewTab(),
                      _buildSalesTab(),
                      _buildInventoryTab(),
                      _buildCrossStoreTab(),
                    ]
                  : [
                      _buildOverviewTab(),
                      _buildSalesTab(),
                      _buildInventoryTab(),
                    ],
            )
          : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: const AppBottomNav(currentRoute: '/analytics'),
      floatingActionButton: authProvider.role == UserRole.superadmin ||
              authProvider.role == UserRole.admin
          ? FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.of(context).pushNamed('/analytics/events'),
              label: const Text('Events Dashboard'),
              icon: const Icon(Icons.bar_chart),
              backgroundColor: AppColors.primaryBrand,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _buildOverviewTab() {
    return Consumer<AnalyticsProvider>(
      builder: (context, analyticsProvider, child) {
        if (analyticsProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (analyticsProvider.errorMessage != null) {
          return Center(child: Text(analyticsProvider.errorMessage!));
        }

        final salesData = analyticsProvider.salesData;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Key Metrics',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'Total Sales',
                      '${salesData['total_sales'] ?? 0}',
                      Icons.shopping_cart,
                      AppColors.primaryBrand,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMetricCard(
                      'Total Revenue',
                      '\$${_safeDouble(salesData['total_revenue']).toStringAsFixed(2)}',
                      Icons.attach_money,
                      AppColors.primaryAction,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'Average Sale',
                      '\$${_safeDouble(salesData['average_sale']).toStringAsFixed(2)}',
                      Icons.trending_up,
                      AppColors.secondaryAccent,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMetricCard(
                      'Low Stock Items',
                      () {
                        try {
                          final inventoryProvider =
                              Provider.of<InventoryProviderV2>(context,
                                  listen: false);
                          return inventoryProvider.lowStockCount.toString();
                        } catch (e) {
                          return '0';
                        }
                      }(),
                      Icons.warning,
                      AppColors.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Daily Sales Trend',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: _buildSalesLineChart(salesData['daily_sales'] ?? []),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSalesTab() {
    return Consumer<AnalyticsProvider>(
      builder: (context, analyticsProvider, child) {
        if (analyticsProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (analyticsProvider.errorMessage != null) {
          return Center(child: Text(analyticsProvider.errorMessage!));
        }

        final topProducts = analyticsProvider.topProducts;
        final recentSales = analyticsProvider.recentSales;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Top Products',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (topProducts.isNotEmpty)
                SizedBox(
                  height: 200,
                  child: _buildTopProductsChart(topProducts),
                )
              else
                const Center(child: Text('No sales data available')),
              const SizedBox(height: 24),
              const Text('Recent Sales',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentSales.length,
                itemBuilder: (context, index) {
                  final sale = recentSales[index];
                  return Card(
                    child: ListTile(
                      title: Text('Sale #${sale['id'] ?? 'N/A'}'),
                      subtitle: Text(
                          '${sale['items_count'] ?? 0} items • \$${_safeDouble(sale['total_amount']).toStringAsFixed(2)}'),
                      trailing: Text(_formatDate(sale['created_at'] ?? '')),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInventoryTab() {
    return Consumer<AnalyticsProvider>(
      builder: (context, analyticsProvider, child) {
        if (analyticsProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (analyticsProvider.errorMessage != null) {
          return Center(child: Text(analyticsProvider.errorMessage!));
        }

        final inventoryAlerts = <Map<String, dynamic>>[];
        try {
          final inventoryProvider =
              Provider.of<InventoryProviderV2>(context, listen: false);
          // Use the new getter that provides products as maps
          inventoryAlerts
              .addAll(inventoryProvider.lowStockAlertsAsMaps.map((product) {
            return {
              ...product,
              'alert_level':
                  (product['stock_quantity'] as int) < 3 ? 'Critical' : 'Low',
            };
          }));
        } catch (e) {
          // InventoryProvider not available, use empty list
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Inventory Alerts',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (inventoryAlerts.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text('All inventory levels are good!',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.primaryAction)),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: inventoryAlerts.length,
                  itemBuilder: (context, index) {
                    final alert = inventoryAlerts[index];
                    return Card(
                      color: alert['alert_level'] == 'Low'
                          ? AppColors.warning.withValues(alpha: 0.08 * 255)
                          : AppColors.secondaryAccent
                              .withValues(alpha: 0.08 * 255),
                      child: ListTile(
                        leading: Icon(
                          Icons.warning,
                          color: alert['alert_level'] == 'Low'
                              ? AppColors.warning
                              : AppColors.secondaryAccent,
                        ),
                        title: Text(alert['name'] ?? 'Unknown Product'),
                        subtitle: Text(
                            'Stock: ${alert['stock_quantity']} • ${alert['alert_level']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () {
                            // Navigate to edit product screen
                            Navigator.of(context).pushNamed(
                              '/edit_product',
                              arguments: {'id': alert['id']},
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCard(
      String title, String value, IconData icon, Color color) {
    // Use shared MetricCard component for visual consistency
    return MetricCard(title: title, value: value, icon: icon, color: color);
  }

  Widget _buildSalesLineChart(List<dynamic> dailySales) {
    if (dailySales.isEmpty) {
      return const Center(child: Text('No sales data available'));
    }

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text('\$${value.toInt()}');
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() < dailySales.length) {
                  final dateStr =
                      (dailySales[value.toInt()]['date'] ?? '').toString();
                  return Text(dateStr.contains('-')
                      ? dateStr.split('-').last
                      : dateStr);
                }
                return const Text('');
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: dailySales.asMap().entries.map((entry) {
              return FlSpot(
                  entry.key.toDouble(), _safeDouble(entry.value['revenue']));
            }).toList(),
            isCurved: true,
            color: AppColors.primaryBrand,
            barWidth: 4,
            belowBarData: BarAreaData(
                show: true,
                color: AppColors.primaryBrand.withValues(alpha: 0.1 * 255)),
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProductsChart(List<Map<String, dynamic>> topProducts) {
    if (topProducts.isEmpty) {
      return const Center(child: Text('No product data available'));
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: topProducts.isNotEmpty
            ? topProducts
                    .map((p) => _safeInt(p['sales_count']))
                    .reduce((a, b) => a > b ? a : b)
                    .toDouble() *
                1.2
            : 10,
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() < topProducts.length) {
                  final name =
                      (topProducts[value.toInt()]['name'] ?? '').toString();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      name.split(' ').first,
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                return Text(value.toInt().toString());
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: topProducts.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: (entry.value['sales_count'] ?? 0).toDouble(),
                color: AppColors.primaryBrand,
                width: 16,
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCrossStoreTab() {
    final analyticsProvider = Provider.of<AnalyticsProvider>(context);

    return RefreshIndicator(
      onRefresh: () => analyticsProvider.loadCrossStoreAnalytics(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cross-Store Analytics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Global view across all stores (Superadmin Only)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6 * 255)),
            ),
            const SizedBox(height: 24),

            // Global metrics cards
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    'Total Sales',
                    analyticsProvider.salesData['total_sales']?.toString() ??
                        '0',
                    Icons.shopping_cart,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    'Total Revenue',
                    _formatCurrency(
                        analyticsProvider.salesData['total_revenue']),
                    Icons.attach_money,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Store comparison section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Store Performance Comparison',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () =>
                          analyticsProvider.loadStoreComparisonAnalytics(),
                      icon: const Icon(Icons.compare),
                      label: const Text('Compare All Stores'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Recent sales across all stores
            const Text(
              'Recent Sales (All Stores)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...analyticsProvider.recentSales
                .take(10)
                .map((sale) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.receipt),
                        title: Text('Sale #${sale['id']}'),
                        subtitle: Text(_formatDate(sale['created_at'] ?? '')),
                        trailing: Text(_formatCurrency(sale['total'])),
                      ),
                    ))
                .toList(),
          ],
        ),
      ),
    );
  }

  double _safeDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  int _safeInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      return int.tryParse(v) ?? (double.tryParse(v)?.toInt() ?? 0);
    }
    return 0;
  }

  String _formatCurrency(dynamic v) {
    return '\$${_safeDouble(v).toStringAsFixed(2)}';
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.month}/${date.day}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }
}
