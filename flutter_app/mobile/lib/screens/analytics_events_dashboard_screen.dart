import 'package:flutter/material.dart';
import 'package:mobile/widgets/all_stores_banner.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/widgets/store_badge.dart';
import 'dart:math';

class AnalyticsEventsDashboardScreen extends StatefulWidget {
  const AnalyticsEventsDashboardScreen({super.key});

  @override
  State<AnalyticsEventsDashboardScreen> createState() =>
      _AnalyticsEventsDashboardScreenState();
}

class _AnalyticsEventsDashboardScreenState
    extends State<AnalyticsEventsDashboardScreen> {
  bool _loading = false;
  Map<String, dynamic>? _summary;

  int _selectedDays = 7; // default last 7 days

  // Simple tooltip text shown when interacting with charts (for accessibility and tests)
  String? _lastTooltipText;

  Future<void> _loadSummary() async {
    final analyticsProvider = context.read<AnalyticsProvider>();
    setState(() => _loading = true);
    try {
      debugPrint(
          'AnalyticsEventsDashboard: calling analyticsProvider.loadAnalyticsSummary');
      final data = await analyticsProvider.loadAnalyticsSummary(
          'store_quick_switch',
          sinceDays: _selectedDays,
          granularity: 'daily');
      debugPrint('AnalyticsEventsDashboard: loaded summary $data');
      setState(() {
        _summary = data;
        _loading = false;
      });
    } catch (e) {
      debugPrint('AnalyticsEventsDashboard: failed to load summary: $e');
      setState(() {
        _summary = null;
        _loading = false;
      });
    }
  }

  void _setRange(int days) {
    setState(() => _selectedDays = days);
    _loadSummary();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      debugPrint('AnalyticsEventsDashboard: post frame callback');
      final analyticsProvider = context.read<AnalyticsProvider>();
      debugPrint('AnalyticsEventsDashboard: got analyticsProvider');
      final authProvider = context.read<AuthProvider>();
      debugPrint('AnalyticsEventsDashboard: got authProvider');
      final storeProvider = context.read<StoreProvider>();
      debugPrint('AnalyticsEventsDashboard: got storeProvider');

      // Avoid forcing store initialization here (tests inject fake providers without network access)
      analyticsProvider.setAuthProvider(authProvider);
      analyticsProvider.setStoreProvider(storeProvider);

      await _loadSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final role = authProvider.role;

    if (role != 'superadmin' && role != 'admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Analytics Dashboard')),
        body: const Center(child: Text('Access denied')),
      );
    }

    final storeProvider = context.watch<StoreProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics Dashboard'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: StoreIndicator(store: storeProvider.currentStore),
                ),
                if (context.watch<AuthProvider>().role == 'superadmin' ||
                    context.watch<AuthProvider>().role == 'admin')
                  const StoreQuickAction(),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _buildDashboardBody(storeProvider),
      ),
      bottomNavigationBar: const AppBottomNav(currentRoute: '/analytics'),
    );
  }

  Widget _buildDashboardBody(StoreProvider storeProvider) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_summary == null) return const Center(child: Text('No data'));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // All Stores banner when in global view
          if (storeProvider.currentStore == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12.0),
              child: AllStoresBanner(),
            ),
          Text('Event: ${_summary!['event_name']}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Total Events: ${_summary!['total_count'] ?? 0}'),
          const SizedBox(height: 8),
          Text(
              'Average Duration (ms): ${_summary!['avg_duration_ms'] ?? 'N/A'}'),
          const SizedBox(height: 16),
          const Text('By Store:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // Range selector (wraps on narrow widths)
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: () => _setRange(7),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedDays == 7
                        ? Colors.blue[800]
                        : Colors.grey[300],
                    foregroundColor:
                        _selectedDays == 7 ? Colors.white : Colors.black),
                child: Semantics(label: 'Last 7 days', child: const Text('7d')),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _setRange(30),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedDays == 30
                        ? Colors.blue[800]
                        : Colors.grey[300],
                    foregroundColor:
                        _selectedDays == 30 ? Colors.white : Colors.black),
                child:
                    Semantics(label: 'Last 30 days', child: const Text('30d')),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _setRange(90),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedDays == 90
                        ? Colors.blue[800]
                        : Colors.grey[300],
                    foregroundColor:
                        _selectedDays == 90 ? Colors.white : Colors.black),
                child:
                    Semantics(label: 'Last 90 days', child: const Text('90d')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Minimal bar chart visualization using fl_chart with touch tooltips
          SizedBox(
            height: MediaQuery.of(context).size.height < 400
                ? max(100.0, MediaQuery.of(context).size.height * 0.22)
                : 140.0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return GestureDetector(
                          key: const Key('barChartGesture'),
                          onTapDown: (details) {
                            final local = details.localPosition;
                            final width = constraints.maxWidth;
                            final n = (_summary!['by_store'] as List).length;
                            int idx = 0;
                            if (n > 0) {
                              if (width > 0) {
                                idx = (local.dx / (width / n))
                                    .floor()
                                    .clamp(0, n - 1);
                              } else {
                                idx = 0;
                              }
                              final item = (_summary!['by_store'] as List)[idx];
                              setState(() {
                                _lastTooltipText =
                                    'Store ${item['store_id'] ?? 'global'}: ${(item['count'] as num).toInt()}';
                              });
                            }
                          },
                          child: _buildBarChart(_summary!['by_store'] as List),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Semantics(
                      label: 'Chart tooltip',
                      child: Container(
                        key: const Key('chartTooltip'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: _lastTooltipText != null
                              ? Colors.black87
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_lastTooltipText ?? '',
                            style: TextStyle(
                                color: _lastTooltipText != null
                                    ? Colors.white
                                    : Colors.transparent)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: MediaQuery.of(context).size.height < 400
                ? max(120.0, MediaQuery.of(context).size.height * 0.35)
                : 200.0,
            child: ListView.builder(
              itemCount: (_summary!['by_store'] as List).length,
              itemBuilder: (context, index) {
                final b = (_summary!['by_store'] as List)[index];
                return ListTile(
                  title: Text('Store ${b['store_id'] ?? 'global'}'),
                  subtitle: b['series'] != null
                      ? Semantics(
                          label: 'Sparkline for store ${b['store_id']}',
                          child: SizedBox(
                            height: 48,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final series = (b['series'] as List?) ?? [];
                                  return GestureDetector(
                                    key: const Key('lineChartGesture'),
                                    onTapDown: (details) {
                                      final local = details.localPosition;
                                      final width = constraints.maxWidth;
                                      final n = series.length;
                                      int idx = 0;
                                      if (n > 0) {
                                        if (width > 0) {
                                          idx = (local.dx / (width / n))
                                              .floor()
                                              .clamp(0, n - 1);
                                        } else {
                                          idx = 0;
                                        }
                                        final val = series[idx];
                                        setState(() {
                                          _lastTooltipText =
                                              'Store ${b['store_id'] ?? 'global'}: ${val.toInt()}';
                                        });
                                      }
                                    },
                                    child: LineChart(LineChartData(
                                      gridData: const FlGridData(show: false),
                                      borderData: FlBorderData(show: false),
                                      titlesData:
                                          const FlTitlesData(show: false),
                                      lineBarsData: [
                                        LineChartBarData(
                                          spots: List.generate(
                                              (b['series'] as List).length,
                                              (i) => FlSpot(
                                                  i.toDouble(),
                                                  (b['series'][i] as num)
                                                      .toDouble())),
                                          isCurved: false,
                                          color: Colors.blue[800],
                                          barWidth: 2,
                                          dotData: const FlDotData(show: false),
                                        ),
                                      ],
                                      minY: 0,
                                    )),
                                  );
                                },
                              ),
                            ),
                          ),
                        )
                      : null,
                  trailing: Text('${b['count']}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List byStore) {
    if (byStore.isEmpty) {
      return const Center(child: Text('No data'));
    }

    // Map store entries to bars
    final groups = <BarChartGroupData>[];
    final maxCount = byStore
        .map((e) => (e['count'] as num).toDouble())
        .fold<double>(0, (prev, el) => max(prev, el.toDouble()));

    for (var i = 0; i < byStore.length; i++) {
      final item = byStore[i];
      final count = (item['count'] as num).toDouble();
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: count,
              color: Colors.blueAccent,
              width: 18,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        maxY: max(1, maxCount * 1.2),
        barGroups: groups,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: Colors.black87,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label =
                  byStore[group.x.toInt()]['store_id']?.toString() ?? 'G';
              return BarTooltipItem('$label\n${rod.toY.toInt()}',
                  const TextStyle(color: Colors.white));
            },
          ),
          touchCallback: (event, response) {
            if (response != null && response.spot != null) {
              final idx = response.spot!.touchedBarGroupIndex;
              if (idx >= 0 && idx < byStore.length) {
                final item = byStore[idx];
                setState(() {
                  _lastTooltipText =
                      'Store ${item['store_id'] ?? 'global'}: ${(item['count'] as num).toInt()}';
                });
              }
            }
          },
        ),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= byStore.length) {
                  return const SizedBox.shrink();
                }
                final label = byStore[idx]['store_id']?.toString() ?? 'G';
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 6,
                  child: Text(label, style: const TextStyle(fontSize: 12)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
