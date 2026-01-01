/// Model for tracking sync conflicts that require manual resolution
class SyncConflict {
  final String resourceType; // 'user', 'product', 'sale', 'store'
  final int localId;
  final int? serverId;
  final String? clientId;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> serverData;
  final DateTime localUpdatedAt;
  final DateTime serverUpdatedAt;
  final DateTime detectedAt;

  SyncConflict({
    required this.resourceType,
    required this.localId,
    this.serverId,
    this.clientId,
    required this.localData,
    required this.serverData,
    required this.localUpdatedAt,
    required this.serverUpdatedAt,
    required this.detectedAt,
  });

  /// Create from JSON
  factory SyncConflict.fromJson(Map<String, dynamic> json) {
    return SyncConflict(
      resourceType: json['resource_type'] as String,
      localId: json['local_id'] as int,
      serverId: json['server_id'] as int?,
      clientId: json['client_id'] as String?,
      localData: json['local_data'] as Map<String, dynamic>,
      serverData: json['server_data'] as Map<String, dynamic>,
      localUpdatedAt: DateTime.parse(json['local_updated_at'] as String),
      serverUpdatedAt: DateTime.parse(json['server_updated_at'] as String),
      detectedAt: DateTime.parse(json['detected_at'] as String),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'resource_type': resourceType,
      'local_id': localId,
      'server_id': serverId,
      'client_id': clientId,
      'local_data': localData,
      'server_data': serverData,
      'local_updated_at': localUpdatedAt.toIso8601String(),
      'server_updated_at': serverUpdatedAt.toIso8601String(),
      'detected_at': detectedAt.toIso8601String(),
    };
  }

  /// Get a human-readable description of the conflict
  String getDescription() {
    final timeDiff = serverUpdatedAt.difference(localUpdatedAt);
    final diffMinutes = timeDiff.inMinutes.abs();

    if (diffMinutes < 1) {
      return 'Simultaneous changes detected';
    } else if (timeDiff.isNegative) {
      return 'Local version is $diffMinutes minutes newer';
    } else {
      return 'Server version is $diffMinutes minutes newer';
    }
  }

  /// Get list of conflicting fields
  List<String> getConflictingFields() {
    final conflicts = <String>[];
    
    for (final key in localData.keys) {
      if (serverData.containsKey(key)) {
        if (localData[key] != serverData[key]) {
          conflicts.add(key);
        }
      }
    }
    
    return conflicts;
  }

  /// Get a summary of changes for display
  String getFieldSummary(String fieldName) {
    final localValue = localData[fieldName];
    final serverValue = serverData[fieldName];
    
    return 'Local: ${_formatValue(localValue)} → Server: ${_formatValue(serverValue)}';
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    if (value is DateTime) return value.toLocal().toString();
    return value.toString();
  }
}

/// Conflict resolution strategy
enum ConflictResolution {
  useLocal,     // Keep local changes, discard server changes
  useServer,    // Discard local changes, use server changes
  merge,        // Merge both changes (manual field selection)
  skip,         // Skip for now, resolve later
}

/// Result of conflict resolution
class ConflictResolutionResult {
  final SyncConflict conflict;
  final ConflictResolution resolution;
  final Map<String, dynamic>? mergedData; // Only for merge strategy

  ConflictResolutionResult({
    required this.conflict,
    required this.resolution,
    this.mergedData,
  });

  bool get isMerge => resolution == ConflictResolution.merge;
  bool get isLocal => resolution == ConflictResolution.useLocal;
  bool get isServer => resolution == ConflictResolution.useServer;
  bool get isSkip => resolution == ConflictResolution.skip;

  Map<String, dynamic> getFinalData() {
    switch (resolution) {
      case ConflictResolution.useLocal:
        return conflict.localData;
      case ConflictResolution.useServer:
        return conflict.serverData;
      case ConflictResolution.merge:
        return mergedData ?? conflict.localData;
      case ConflictResolution.skip:
        return conflict.localData; // Keep local for now
    }
  }
}

/// Service for managing sync conflicts
class ConflictManager {
  final List<SyncConflict> _conflicts = [];

  /// Add a new conflict
  void addConflict(SyncConflict conflict) {
    _conflicts.add(conflict);
  }

  /// Get all pending conflicts
  List<SyncConflict> getPendingConflicts() {
    return List.unmodifiable(_conflicts);
  }

  /// Get conflicts by resource type
  List<SyncConflict> getConflictsByType(String resourceType) {
    return _conflicts.where((c) => c.resourceType == resourceType).toList();
  }

  /// Get conflict count
  int getConflictCount() => _conflicts.length;

  /// Check if there are any conflicts
  bool hasConflicts() => _conflicts.isNotEmpty;

  /// Remove a resolved conflict
  void removeConflict(SyncConflict conflict) {
    _conflicts.removeWhere((c) => 
      c.resourceType == conflict.resourceType && 
      c.localId == conflict.localId
    );
  }

  /// Clear all conflicts
  void clearAll() {
    _conflicts.clear();
  }

  /// Get conflicts requiring immediate attention (older than threshold)
  List<SyncConflict> getUrgentConflicts({Duration threshold = const Duration(hours: 24)}) {
    final now = DateTime.now();
    return _conflicts.where((c) {
      final age = now.difference(c.detectedAt);
      return age > threshold;
    }).toList();
  }
}
