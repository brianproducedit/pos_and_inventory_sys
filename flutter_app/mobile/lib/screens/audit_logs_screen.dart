import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile/services/time_service.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/audit_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:mobile/widgets/store_badge.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';

class AuditLogsScreen extends StatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isFilterExpanded = false;

  // Filter controllers
  int? _selectedUserId;
  String? _selectedAction;
  String? _selectedResourceType;
  DateTime? _startDate;
  DateTime? _endDate;

  List<String> _availableActions = [];
  List<String> _availableResourceTypes = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final auditProvider = context.read<AuditProvider>();
    final storeProvider = context.read<StoreProvider>();

    // Ensure store provider is initialized and provide it to audit provider
    try {
      if (!storeProvider.isInitialized) {
        unawaited(storeProvider.initialize());
      }
    } catch (e) {
      debugPrint('AuditLogs: store init skipped: $e');
    }
    auditProvider.setStoreProvider(storeProvider);

    await Future.wait([
      auditProvider.loadAuditLogs(refresh: true),
      _loadFilterOptions(),
    ]);
  }

  Future<void> _loadFilterOptions() async {
    final auditProvider = context.read<AuditProvider>();
    _availableActions = await auditProvider.getAuditActions();
    _availableResourceTypes = await auditProvider.getResourceTypes();
    setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      context.read<AuditProvider>().loadNextPage();
    }
  }

  void _applyFilters() {
    context.read<AuditProvider>().setFilters(
          userId: _selectedUserId,
          action: _selectedAction,
          resourceType: _selectedResourceType,
          startDate: _startDate,
          endDate: _endDate,
        );
  }

  void _clearFilters() {
    setState(() {
      _selectedUserId = null;
      _selectedAction = null;
      _selectedResourceType = null;
      _startDate = null;
      _endDate = null;
    });
    context.read<AuditProvider>().clearFilters();
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: TimeService.instance.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  String _formatAction(String action) {
    return action
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  String _formatResourceType(String resourceType) {
    return resourceType[0].toUpperCase() + resourceType.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final auditProvider = context.watch<AuditProvider>();

    // Only superadmin and admin can access this screen
    if (authProvider.role != 'superadmin' && authProvider.role != 'admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Text('You do not have permission to access this screen.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Logs'),
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
                    if (context.watch<AuthProvider>().role == 'superadmin' ||
                        context.watch<AuthProvider>().role == 'admin')
                      const StoreQuickAction(),
                    IconButton(
                      icon: Icon(
                        _isFilterExpanded
                            ? Icons.filter_list_off
                            : Icons.filter_list,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          _isFilterExpanded = !_isFilterExpanded;
                        });
                      },
                    ),
                    if (_isFilterExpanded)
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white),
                        onPressed: _clearFilters,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_isFilterExpanded) _buildFilters(),
          Expanded(
            child: auditProvider.isLoading && auditProvider.auditLogs.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : auditProvider.error != null
                    ? _buildErrorWidget()
                    : _buildAuditLogsList(),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentRoute: '/audit_logs'),
    );
  }

  Widget _buildFilters() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filters',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // Action dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedAction,
              decoration: const InputDecoration(
                labelText: 'Action',
                border: OutlineInputBorder(),
              ),
              items: _availableActions.map((action) {
                return DropdownMenuItem(
                  value: action,
                  child: Text(_formatAction(action)),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedAction = value;
                });
              },
            ),
            const SizedBox(height: 16),
            // Resource Type dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedResourceType,
              decoration: const InputDecoration(
                labelText: 'Resource Type',
                border: OutlineInputBorder(),
              ),
              items: _availableResourceTypes.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(_formatResourceType(type)),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedResourceType = value;
                });
              },
            ),
            const SizedBox(height: 16),
            // Date range and Apply button
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      _startDate != null && _endDate != null
                          ? '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}'
                          : 'Select Date Range',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => _selectDateRange(context),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _applyFilters,
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    final auditProvider = context.watch<AuditProvider>();
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('Error: ${auditProvider.error}'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              auditProvider.clearError();
              _loadInitialData();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditLogsList() {
    final auditProvider = context.watch<AuditProvider>();

    if (auditProvider.auditLogs.isEmpty) {
      return const Center(
        child: Text('No audit logs found.'),
      );
    }

    return RefreshIndicator(
      onRefresh: () => auditProvider.loadAuditLogs(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: auditProvider.auditLogs.length +
            (auditProvider.hasNextPage ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == auditProvider.auditLogs.length) {
            // Loading indicator for next page
            if (auditProvider.isLoading) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            return const SizedBox.shrink();
          }

          final log = auditProvider.auditLogs[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatAction(log.action),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        DateFormat('MMM dd, HH:mm').format(log.createdAt),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatResourceType(log.resourceType)} ${log.resourceId != null ? '#${log.resourceId}' : ''}',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  if (log.username != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'User: ${log.username}',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ],
                  if (log.details != null && log.details!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        log.details.toString(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  if (log.ipAddress != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'IP: ${log.ipAddress}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
