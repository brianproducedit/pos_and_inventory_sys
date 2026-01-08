import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data_protection_service.dart';

/// Wrapper that adds safety mechanisms around sync operations.
///
/// Features:
/// 1. Pre-sync backup creation
/// 2. Transaction rollback on failure
/// 3. Idempotency enforcement
/// 4. Conflict preservation
/// 5. Retry with exponential backoff
/// 6. Sync state recovery
class SyncSafetyWrapper {
  final DataProtectionService _dataProtection;

  static const int _maxRetries = 5;
  static const Duration _baseRetryDelay = Duration(seconds: 2);

  SyncSafetyWrapper(this._dataProtection);

  // ═══════════════════════════════════════════════════════════════════════════
  // SAFE SYNC EXECUTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Execute a sync operation with full safety guarantees
  Future<SafeSyncResult<T>> executeSafeSync<T>({
    required String operationId,
    required Future<T> Function() syncOperation,
    required List<Map<String, dynamic>> changes,
    bool createBackupFirst = true,
    bool allowRetry = true,
  }) async {
    debugPrint('🔒 Starting safe sync: $operationId');

    // 1. Check for idempotency (don't process same operation twice)
    if (await _isOperationCompleted(operationId)) {
      debugPrint('⏭️ Operation $operationId already completed, skipping');
      return SafeSyncResult(
        success: true,
        skipped: true,
        message: 'Operation already completed',
      );
    }

    // 2. Create backup before sync if requested
    if (createBackupFirst) {
      final backupResult = await _dataProtection.createBackup(
        reason: 'pre_sync_$operationId',
      );
      if (!backupResult.success) {
        debugPrint(
            '⚠️ Pre-sync backup failed, continuing anyway: ${backupResult.error}');
      }
    }

    // 3. Start sync journal
    final journal = await _dataProtection.startSyncJournal(
      operationType: operationId,
      changes: changes,
    );

    // 4. Execute with retry logic
    int attempt = 0;
    Exception? lastError;

    while (attempt < (allowRetry ? _maxRetries : 1)) {
      attempt++;

      try {
        debugPrint('🔄 Sync attempt $attempt/$_maxRetries for $operationId');

        // Execute the actual sync operation
        final result = await syncOperation();

        // Mark operation as completed (idempotency)
        await _markOperationCompleted(operationId);

        // Complete journal
        await _dataProtection.completeSyncJournal(journal);

        debugPrint('✅ Safe sync completed: $operationId');
        return SafeSyncResult(
          success: true,
          data: result,
          attempts: attempt,
        );
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('❌ Sync attempt $attempt failed: $e');

        if (attempt < _maxRetries && allowRetry) {
          // Exponential backoff
          final delay = _baseRetryDelay * (1 << (attempt - 1));
          debugPrint('⏳ Retrying in ${delay.inSeconds}s...');
          await Future.delayed(delay);
        }
      }
    }

    // All retries exhausted - mark journal as failed
    await _dataProtection.failSyncJournal(
      journal,
      lastError?.toString() ?? 'Unknown error',
    );

    return SafeSyncResult(
      success: false,
      error: lastError,
      attempts: attempt,
      message: 'Sync failed after $attempt attempts',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BATCH SYNC WITH CHECKPOINTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Execute a batch sync with checkpoint recovery
  Future<BatchSyncResult> executeBatchSyncWithCheckpoints<T>({
    required String batchId,
    required List<SyncBatchItem<T>> items,
    required Future<T> Function(SyncBatchItem<T> item) processItem,
    int checkpointInterval = 10,
  }) async {
    debugPrint('📦 Starting batch sync: $batchId with ${items.length} items');

    // Load checkpoint if exists
    final checkpoint = await _loadCheckpoint(batchId);
    int startIndex = checkpoint?.lastProcessedIndex ?? 0;

    if (startIndex > 0) {
      debugPrint('📍 Resuming from checkpoint: index $startIndex');
    }

    final results = <SyncBatchItemResult<T>>[];
    int successCount = 0;
    int failureCount = 0;

    for (int i = startIndex; i < items.length; i++) {
      final item = items[i];

      try {
        final result = await processItem(item);
        results.add(SyncBatchItemResult(
          item: item,
          success: true,
          result: result,
        ));
        successCount++;
      } catch (e) {
        results.add(SyncBatchItemResult(
          item: item,
          success: false,
          error: e.toString(),
        ));
        failureCount++;
      }

      // Save checkpoint periodically
      if ((i + 1) % checkpointInterval == 0) {
        await _saveCheckpoint(
            batchId,
            BatchCheckpoint(
              batchId: batchId,
              lastProcessedIndex: i,
              totalItems: items.length,
              successCount: successCount,
              failureCount: failureCount,
              savedAt: DateTime.now(),
            ));
        debugPrint('💾 Checkpoint saved at index $i');
      }
    }

    // Clear checkpoint on completion
    await _clearCheckpoint(batchId);

    debugPrint(
        '✅ Batch sync completed: $successCount success, $failureCount failures');
    return BatchSyncResult(
      batchId: batchId,
      totalItems: items.length,
      successCount: successCount,
      failureCount: failureCount,
      results: results,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFLICT HANDLING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Handle a sync conflict with data preservation
  Future<ConflictResolution> handleConflict({
    required String resourceType,
    required String resourceId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
    ConflictResolutionStrategy strategy =
        ConflictResolutionStrategy.preserveBoth,
  }) async {
    debugPrint('⚠️ Handling conflict for $resourceType/$resourceId');

    // Always preserve conflict data first (never lose data)
    await _dataProtection.preserveConflict(
      resourceType: resourceType,
      resourceId: resourceId,
      localData: localData,
      serverData: serverData,
    );

    switch (strategy) {
      case ConflictResolutionStrategy.preferLocal:
        return ConflictResolution(
          strategy: strategy,
          resolvedData: localData,
          preserved: true,
        );

      case ConflictResolutionStrategy.preferServer:
        return ConflictResolution(
          strategy: strategy,
          resolvedData: serverData,
          preserved: true,
        );

      case ConflictResolutionStrategy.preferNewest:
        final localUpdated = DateTime.tryParse(
          localData['last_updated_at']?.toString() ?? '',
        );
        final serverUpdated = DateTime.tryParse(
          serverData['last_updated_at']?.toString() ?? '',
        );

        if (localUpdated != null && serverUpdated != null) {
          return ConflictResolution(
            strategy: strategy,
            resolvedData:
                localUpdated.isAfter(serverUpdated) ? localData : serverData,
            preserved: true,
          );
        }
        // Fallback to server if timestamps unavailable
        return ConflictResolution(
          strategy: strategy,
          resolvedData: serverData,
          preserved: true,
        );

      case ConflictResolutionStrategy.merge:
        // Merge both datasets (local values override server for same keys)
        final merged = Map<String, dynamic>.from(serverData);
        merged.addAll(localData);
        return ConflictResolution(
          strategy: strategy,
          resolvedData: merged,
          preserved: true,
        );

      case ConflictResolutionStrategy.preserveBoth:
        // Keep server data but preserve local for manual resolution
        return ConflictResolution(
          strategy: strategy,
          resolvedData: serverData,
          preserved: true,
          requiresManualResolution: true,
        );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IDEMPOTENCY
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> _isOperationCompleted(String operationId) async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getStringList('completed_operations') ?? [];
    return completed.contains(operationId);
  }

  Future<void> _markOperationCompleted(String operationId) async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getStringList('completed_operations') ?? [];

    // Keep only last 1000 operation IDs to prevent unbounded growth
    if (completed.length >= 1000) {
      completed.removeRange(0, completed.length - 900);
    }

    completed.add(operationId);
    await prefs.setStringList('completed_operations', completed);
  }

  /// Clear operation history (for testing or cleanup)
  Future<void> clearOperationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('completed_operations');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHECKPOINTS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<BatchCheckpoint?> _loadCheckpoint(String batchId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('checkpoint_$batchId');
    if (json == null) return null;
    return BatchCheckpoint.fromJson(jsonDecode(json));
  }

  Future<void> _saveCheckpoint(
      String batchId, BatchCheckpoint checkpoint) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'checkpoint_$batchId', jsonEncode(checkpoint.toJson()));
  }

  Future<void> _clearCheckpoint(String batchId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('checkpoint_$batchId');
  }

  /// Get all pending checkpoints (for recovery)
  Future<List<BatchCheckpoint>> getPendingCheckpoints() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('checkpoint_'));

    final checkpoints = <BatchCheckpoint>[];
    for (final key in keys) {
      final json = prefs.getString(key);
      if (json != null) {
        checkpoints.add(BatchCheckpoint.fromJson(jsonDecode(json)));
      }
    }

    return checkpoints;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC STATE VERIFICATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Verify sync state consistency
  Future<SyncStateVerification> verifySyncState({
    required int localItemCount,
    required int serverItemCount,
    required int pendingSyncCount,
  }) async {
    final issues = <String>[];

    // Check for significant discrepancy
    final expectedServerCount = localItemCount - pendingSyncCount;
    final discrepancy = (serverItemCount - expectedServerCount).abs();

    if (discrepancy > 10) {
      issues.add(
          'Significant count discrepancy: expected ~$expectedServerCount on server, found $serverItemCount');
    }

    // Check for stuck sync items
    final pendingCheckpoints = await getPendingCheckpoints();
    for (final checkpoint in pendingCheckpoints) {
      if (DateTime.now().difference(checkpoint.savedAt).inHours > 24) {
        issues.add(
            'Stale checkpoint found: ${checkpoint.batchId} from ${checkpoint.savedAt}');
      }
    }

    return SyncStateVerification(
      isConsistent: issues.isEmpty,
      issues: issues,
      localCount: localItemCount,
      serverCount: serverItemCount,
      pendingCount: pendingSyncCount,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

class SafeSyncResult<T> {
  final bool success;
  final bool skipped;
  final T? data;
  final Exception? error;
  final int? attempts;
  final String? message;

  SafeSyncResult({
    required this.success,
    this.skipped = false,
    this.data,
    this.error,
    this.attempts,
    this.message,
  });
}

class SyncBatchItem<T> {
  final String id;
  final T data;
  final Map<String, dynamic>? metadata;

  SyncBatchItem({
    required this.id,
    required this.data,
    this.metadata,
  });
}

class SyncBatchItemResult<T> {
  final SyncBatchItem<T> item;
  final bool success;
  final T? result;
  final String? error;

  SyncBatchItemResult({
    required this.item,
    required this.success,
    this.result,
    this.error,
  });
}

class BatchSyncResult<T> {
  final String batchId;
  final int totalItems;
  final int successCount;
  final int failureCount;
  final List<SyncBatchItemResult<T>> results;

  BatchSyncResult({
    required this.batchId,
    required this.totalItems,
    required this.successCount,
    required this.failureCount,
    required this.results,
  });

  bool get isFullySuccessful => failureCount == 0;
  bool get isPartiallySuccessful => successCount > 0 && failureCount > 0;
  bool get isTotalFailure => successCount == 0;
}

class BatchCheckpoint {
  final String batchId;
  final int lastProcessedIndex;
  final int totalItems;
  final int successCount;
  final int failureCount;
  final DateTime savedAt;

  BatchCheckpoint({
    required this.batchId,
    required this.lastProcessedIndex,
    required this.totalItems,
    required this.successCount,
    required this.failureCount,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'batchId': batchId,
        'lastProcessedIndex': lastProcessedIndex,
        'totalItems': totalItems,
        'successCount': successCount,
        'failureCount': failureCount,
        'savedAt': savedAt.toIso8601String(),
      };

  factory BatchCheckpoint.fromJson(Map<String, dynamic> json) =>
      BatchCheckpoint(
        batchId: json['batchId'] as String,
        lastProcessedIndex: json['lastProcessedIndex'] as int,
        totalItems: json['totalItems'] as int,
        successCount: json['successCount'] as int,
        failureCount: json['failureCount'] as int,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}

enum ConflictResolutionStrategy {
  preferLocal,
  preferServer,
  preferNewest,
  merge,
  preserveBoth,
}

class ConflictResolution {
  final ConflictResolutionStrategy strategy;
  final Map<String, dynamic> resolvedData;
  final bool preserved;
  final bool requiresManualResolution;

  ConflictResolution({
    required this.strategy,
    required this.resolvedData,
    required this.preserved,
    this.requiresManualResolution = false,
  });
}

class SyncStateVerification {
  final bool isConsistent;
  final List<String> issues;
  final int localCount;
  final int serverCount;
  final int pendingCount;

  SyncStateVerification({
    required this.isConsistent,
    required this.issues,
    required this.localCount,
    required this.serverCount,
    required this.pendingCount,
  });
}
