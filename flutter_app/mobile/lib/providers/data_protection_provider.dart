import 'package:flutter/foundation.dart';
import 'package:mobile/db/app_database.dart';

import '../services/data_protection_service.dart';
import '../services/sync_safety_wrapper.dart';

/// Provider for data protection services.
///
/// Manages the lifecycle of data protection features including:
/// - Automatic backups
/// - Sync safety mechanisms
/// - Crash recovery
/// - Data integrity verification
class DataProtectionProvider extends ChangeNotifier {
  final DataProtectionService _dataProtection;
  late final SyncSafetyWrapper _syncSafety;

  bool _isInitialized = false;
  bool _isRunningIntegrityCheck = false;
  IntegrityReport? _lastIntegrityReport;
  List<BackupMetadata> _backups = [];
  String? _lastError;

  DataProtectionProvider({DataProtectionService? dataProtectionService})
      : _dataProtection = dataProtectionService ?? DataProtectionService() {
    _syncSafety = SyncSafetyWrapper(_dataProtection);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get isInitialized => _isInitialized;
  bool get isRunningIntegrityCheck => _isRunningIntegrityCheck;
  IntegrityReport? get lastIntegrityReport => _lastIntegrityReport;
  List<BackupMetadata> get backups => List.unmodifiable(_backups);
  String? get lastError => _lastError;
  DataProtectionService get dataProtection => _dataProtection;
  SyncSafetyWrapper get syncSafety => _syncSafety;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize data protection services
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('📋 DataProtectionProvider: Initializing...');

      // Enable WAL mode for better crash recovery
      await _dataProtection.enableWALMode();

      // Initialize core data protection
      await _dataProtection.initialize();

      // Load backup list
      await refreshBackupList();

      _isInitialized = true;
      _lastError = null;

      debugPrint('✅ DataProtectionProvider: Initialized');
      notifyListeners();
    } catch (e, st) {
      _lastError = e.toString();
      debugPrint('❌ DataProtectionProvider initialization failed: $e\n$st');
      notifyListeners();
    }
  }

  /// Shutdown data protection services
  Future<void> shutdown() async {
    if (!_isInitialized) return;

    try {
      debugPrint('📋 DataProtectionProvider: Shutting down...');
      await _dataProtection.shutdown();
      _isInitialized = false;
      debugPrint('✅ DataProtectionProvider: Shutdown complete');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ DataProtectionProvider shutdown error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BACKUP OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a manual backup
  Future<BackupResult> createBackup({String reason = 'manual'}) async {
    try {
      debugPrint('💾 Creating backup (reason: $reason)...');
      final result = await _dataProtection.createBackup(reason: reason);

      if (result.success) {
        await refreshBackupList();
      } else {
        _lastError = result.error;
      }

      notifyListeners();
      return result;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return BackupResult(success: false, error: e.toString());
    }
  }

  /// Restore from a specific backup
  Future<RestoreResult> restoreFromBackup(BackupMetadata backup) async {
    try {
      debugPrint('🔄 Restoring from backup: ${backup.filename}...');
      final result = await _dataProtection.restoreFromBackup(backup);

      if (!result.success) {
        _lastError = result.error;
      }

      notifyListeners();
      return result;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return RestoreResult(success: false, error: e.toString());
    }
  }

  /// Restore from the latest backup
  Future<RestoreResult> restoreFromLatestBackup() async {
    try {
      debugPrint('🔄 Restoring from latest backup...');
      final result = await _dataProtection.restoreFromLatestBackup();

      if (!result.success) {
        _lastError = result.error;
      }

      notifyListeners();
      return result;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return RestoreResult(success: false, error: e.toString());
    }
  }

  /// Refresh the list of available backups
  Future<void> refreshBackupList() async {
    _backups = await _dataProtection.listBackups();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTEGRITY CHECKS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Run a data integrity check
  Future<IntegrityReport> runIntegrityCheck() async {
    if (_isRunningIntegrityCheck) {
      return _lastIntegrityReport ??
          IntegrityReport(
            checkedAt: DateTime.now(),
            issues: [],
            tablesChecked: [],
          );
    }

    try {
      _isRunningIntegrityCheck = true;
      notifyListeners();

      debugPrint('🔍 Running data integrity check...');
      _lastIntegrityReport = await _dataProtection.verifyDataIntegrity();

      _isRunningIntegrityCheck = false;
      notifyListeners();

      return _lastIntegrityReport!;
    } catch (e) {
      _isRunningIntegrityCheck = false;
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UNINSTALL PROTECTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export data for uninstall protection
  Future<ExportResult> exportForUninstallProtection() async {
    try {
      debugPrint('📤 Exporting data for uninstall protection...');
      final result = await _dataProtection.exportForUninstallProtection();

      if (!result.success) {
        _lastError = result.error;
      }

      notifyListeners();
      return result;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return ExportResult(success: false, error: e.toString());
    }
  }

  /// Import data after reinstall
  Future<ImportResult> importAfterReinstall() async {
    try {
      debugPrint('📥 Importing data after reinstall...');
      final result = await _dataProtection.importAfterReinstall();

      if (!result.success) {
        _lastError = result.error;
      }

      notifyListeners();
      return result;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return ImportResult(success: false, error: e.toString());
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFLICT MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all unresolved conflicts
  Future<Future<List<SyncConflict>>> getUnresolvedConflicts() async {
    return _dataProtection.getUnresolvedConflicts();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATABASE OPTIMIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Checkpoint the WAL file
  Future<void> checkpointWAL() async {
    await _dataProtection.checkpointWAL();
  }

  /// Clear the last error
  void clearError() {
    _lastError = null;
    notifyListeners();
  }
}
