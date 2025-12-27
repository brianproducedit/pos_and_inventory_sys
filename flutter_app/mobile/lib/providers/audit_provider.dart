import 'package:flutter/material.dart';
import 'package:mobile/services/time_service.dart';
import '../services/audit_service.dart';
import 'store_provider.dart';

class AuditLog {
  final int? id;
  final int? userId;
  final String? username;
  final String action;
  final String resourceType;
  final int? resourceId;
  final Map<String, dynamic>? details;
  final String? ipAddress;
  final String? userAgent;
  final DateTime createdAt;

  AuditLog({
    this.id,
    this.userId,
    this.username,
    required this.action,
    required this.resourceType,
    this.resourceId,
    this.details,
    this.ipAddress,
    this.userAgent,
    required this.createdAt,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    // Support both legacy keys (resource_type, resource_id, created_at)
    // and the newer API keys (entity_type, entity_id, timestamp)
    final resourceType = json['resource_type'] ?? json['entity_type'];
    final resourceId = json['resource_id'] ?? json['entity_id'];
    final createdAtRaw = json['created_at'] ?? json['timestamp'];

    DateTime createdAt;
    if (createdAtRaw is String) {
      createdAt = DateTime.parse(createdAtRaw);
    } else if (createdAtRaw is DateTime) {
      createdAt = createdAtRaw;
    } else {
      createdAt = TimeService.instance.now();
    }

    return AuditLog(
      id: json['id'],
      userId: json['user_id'],
      username: json['username'],
      action: json['action'],
      resourceType: resourceType ?? 'unknown',
      resourceId: resourceId,
      details: json['details'] is Map
          ? Map<String, dynamic>.from(json['details'])
          : null,
      ipAddress: json['ip_address'],
      userAgent: json['user_agent'],
      createdAt: createdAt,
    );
  }
}

class AuditProvider with ChangeNotifier {
  final AuditService _auditService = AuditService();

  List<AuditLog> _auditLogs = [];
  bool _isLoading = false;
  String? _error;
  int _totalCount = 0;
  int _currentPage = 0;
  final int _pageSize = 50;

  // Store awareness
  StoreProvider? _storeProvider;
  int? _lastStoreId;

  void _onStoreChanged() {
    final newId = _storeProvider?.currentStore?['id'] as int?;
    if (newId != _lastStoreId) {
      _lastStoreId = newId;
      // Refresh audit logs when store context changes
      loadAuditLogs(refresh: true);
    }
  }

  void setStoreProvider(StoreProvider storeProvider) {
    if (_storeProvider != null) {
      _storeProvider!.removeListener(_onStoreChanged);
    }
    _storeProvider = storeProvider;
    _lastStoreId = _storeProvider?.currentStore?['id'] as int?;
    _storeProvider!.addListener(_onStoreChanged);
  }

  // Filters
  int? _filterUserId;
  String? _filterAction;
  String? _filterResourceType;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  // Getters
  List<AuditLog> get auditLogs => _auditLogs;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get totalCount => _totalCount;
  int get currentPage => _currentPage;
  int get pageSize => _pageSize;
  bool get hasNextPage => (_currentPage + 1) * _pageSize < _totalCount;
  bool get hasPreviousPage => _currentPage > 0;

  // Filter getters
  int? get filterUserId => _filterUserId;
  String? get filterAction => _filterAction;
  String? get filterResourceType => _filterResourceType;
  DateTime? get filterStartDate => _filterStartDate;
  DateTime? get filterEndDate => _filterEndDate;

  Future<void> loadAuditLogs({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 0;
      _auditLogs.clear();
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _auditService.getAuditLogs(
        userId: _filterUserId,
        action: _filterAction,
        resourceType: _filterResourceType,
        startDate: _filterStartDate,
        endDate: _filterEndDate,
        skip: _currentPage * _pageSize,
        limit: _pageSize,
      );

      final logs = (response['logs'] as List)
          .map((log) => AuditLog.fromJson(log))
          .toList();

      if (refresh) {
        _auditLogs = logs;
      } else {
        _auditLogs.addAll(logs);
      }

      _totalCount = response['total_count'] ?? 0;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadNextPage() async {
    if (!hasNextPage || _isLoading) return;
    _currentPage++;
    await loadAuditLogs();
  }

  Future<void> loadPreviousPage() async {
    if (!hasPreviousPage || _isLoading) return;
    _currentPage--;
    await loadAuditLogs();
  }

  void setFilters({
    int? userId,
    String? action,
    String? resourceType,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    _filterUserId = userId;
    _filterAction = action;
    _filterResourceType = resourceType;
    _filterStartDate = startDate;
    _filterEndDate = endDate;
    _currentPage = 0;
    loadAuditLogs(refresh: true);
  }

  void clearFilters() {
    _filterUserId = null;
    _filterAction = null;
    _filterResourceType = null;
    _filterStartDate = null;
    _filterEndDate = null;
    _currentPage = 0;
    loadAuditLogs(refresh: true);
  }

  Future<List<String>> getAuditActions() async {
    return await _auditService.getAuditActions();
  }

  Future<List<String>> getResourceTypes() async {
    return await _auditService.getResourceTypes();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
