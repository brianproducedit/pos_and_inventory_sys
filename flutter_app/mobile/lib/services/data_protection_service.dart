import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';

/// Comprehensive data protection service that prevents data loss across
/// all scenarios: installation, uninstallation, sync failures, and crashes.
///
/// Key features:
/// 1. Automatic backups before critical operations
/// 2. External storage backup for uninstall protection
/// 3. Sync checkpoint recovery
/// 4. Data integrity verification
/// 5. Conflict preservation (never lose conflicting data)
/// 6. Transaction journaling for crash recovery
class DataProtectionService {
  static const String _backupPrefix = 'pos_backup_';
  static const String _journalPrefix = 'sync_journal_';
  static const int _maxBackups = 5;
  static const int _autoBackupIntervalMinutes = 30;

  final FlutterSecureStorage _secureStorage;
  AppDatabase? _db;
  Timer? _autoBackupTimer;
  DateTime? _lastBackupTime;

  DataProtectionService({
    FlutterSecureStorage? secureStorage,
    AppDatabase? database,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _db = database;

  /// Set the database instance (call this after DI setup)
  void setDatabase(AppDatabase db) {
    _db = db;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION & LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize data protection - call on app startup
  Future<void> initialize() async {
    debugPrint('🛡️ DataProtectionService: Initializing...');

    // Check for and recover from any previous crash/incomplete sync
    await _recoverFromCrash();

    // Start automatic backup timer
    _startAutoBackupTimer();

    // Verify data integrity
    await verifyDataIntegrity();

    debugPrint('🛡️ DataProtectionService: Initialized successfully');
  }

  /// Shutdown data protection - call on app termination
  Future<void> shutdown() async {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;

    // Final backup before shutdown
    await createBackup(reason: 'app_shutdown');
  }

  void _startAutoBackupTimer() {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = Timer.periodic(
      const Duration(minutes: _autoBackupIntervalMinutes),
      (_) => _performAutoBackup(),
    );
  }

  Future<void> _performAutoBackup() async {
    final now = DateTime.now();
    if (_lastBackupTime != null &&
        now.difference(_lastBackupTime!).inMinutes <
            _autoBackupIntervalMinutes) {
      return;
    }

    await createBackup(reason: 'auto_periodic');
    _lastBackupTime = now;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BACKUP & RESTORE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get the database directory path
  Future<Directory> _getDatabaseDirectory() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    return dbFolder;
  }

  /// Get the backup directory path (external storage for uninstall protection)
  Future<Directory> _getBackupDirectory() async {
    try {
      // Try to get external storage directory for Android
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final backupDir = Directory(p.join(externalDir.path, 'POS_Backups'));
        if (!await backupDir.exists()) {
          await backupDir.create(recursive: true);
        }
        return backupDir;
      }
    } catch (e) {
      debugPrint('⚠️ External storage not available: $e');
    }

    // Fallback to app documents directory
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(docsDir.path, 'backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Create a full database backup
  Future<BackupResult> createBackup({String reason = 'manual'}) async {
    try {
      debugPrint('💾 Creating backup (reason: $reason)...');

      final dbDir = await _getDatabaseDirectory();
      final backupDir = await _getBackupDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final backupName = '$_backupPrefix${timestamp}_$reason.db';
      final backupPath = p.join(backupDir.path, backupName);

      // Source database file
      final sourceDb = File(p.join(dbDir.path, 'app.sqlite'));
      if (!await sourceDb.exists()) {
        return BackupResult(
          success: false,
          error: 'Source database not found',
        );
      }

      // Copy database file
      await sourceDb.copy(backupPath);

      // Also backup WAL and SHM files if they exist
      final walFile = File(p.join(dbDir.path, 'app.sqlite-wal'));
      final shmFile = File(p.join(dbDir.path, 'app.sqlite-shm'));

      if (await walFile.exists()) {
        await walFile.copy('$backupPath-wal');
      }
      if (await shmFile.exists()) {
        await shmFile.copy('$backupPath-shm');
      }

      // Calculate checksum for integrity verification
      final checksum = await _calculateFileChecksum(sourceDb);

      // Store backup metadata
      final metadata = BackupMetadata(
        filename: backupName,
        timestamp: DateTime.now(),
        reason: reason,
        checksum: checksum,
        sizeBytes: await sourceDb.length(),
      );

      await _saveBackupMetadata(metadata);

      // Cleanup old backups
      await _cleanupOldBackups();

      debugPrint('✅ Backup created: $backupName');
      return BackupResult(
        success: true,
        backupPath: backupPath,
        metadata: metadata,
      );
    } catch (e, st) {
      debugPrint('❌ Backup failed: $e\n$st');
      return BackupResult(success: false, error: e.toString());
    }
  }

  /// Restore from the most recent backup
  Future<RestoreResult> restoreFromLatestBackup() async {
    final backups = await listBackups();
    if (backups.isEmpty) {
      return RestoreResult(
        success: false,
        error: 'No backups available',
      );
    }

    // Sort by timestamp descending
    backups.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return restoreFromBackup(backups.first);
  }

  /// Restore from a specific backup
  Future<RestoreResult> restoreFromBackup(BackupMetadata backup) async {
    try {
      debugPrint('🔄 Restoring from backup: ${backup.filename}...');

      final dbDir = await _getDatabaseDirectory();
      final backupDir = await _getBackupDirectory();
      final backupPath = p.join(backupDir.path, backup.filename);
      final backupFile = File(backupPath);

      if (!await backupFile.exists()) {
        return RestoreResult(
          success: false,
          error: 'Backup file not found: ${backup.filename}',
        );
      }

      // Verify checksum before restore
      final currentChecksum = await _calculateFileChecksum(backupFile);
      if (currentChecksum != backup.checksum) {
        return RestoreResult(
          success: false,
          error: 'Backup file corrupted (checksum mismatch)',
        );
      }

      // Create a safety backup of current database before restore
      await createBackup(reason: 'pre_restore_safety');

      // Close the database connection before restore
      if (_db != null) {
        await _db!.close();
      }

      final targetPath = p.join(dbDir.path, 'app.sqlite');

      // Remove current database files
      final currentDb = File(targetPath);
      final currentWal = File('$targetPath-wal');
      final currentShm = File('$targetPath-shm');

      if (await currentDb.exists()) await currentDb.delete();
      if (await currentWal.exists()) await currentWal.delete();
      if (await currentShm.exists()) await currentShm.delete();

      // Copy backup files
      await backupFile.copy(targetPath);

      final backupWal = File('$backupPath-wal');
      final backupShm = File('$backupPath-shm');

      if (await backupWal.exists()) {
        await backupWal.copy('$targetPath-wal');
      }
      if (await backupShm.exists()) {
        await backupShm.copy('$targetPath-shm');
      }

      debugPrint('✅ Restore completed from: ${backup.filename}');
      return RestoreResult(
        success: true,
        restoredFrom: backup,
      );
    } catch (e, st) {
      debugPrint('❌ Restore failed: $e\n$st');
      return RestoreResult(success: false, error: e.toString());
    }
  }

  /// List all available backups
  Future<List<BackupMetadata>> listBackups() async {
    final prefs = await SharedPreferences.getInstance();
    final metadataJson = prefs.getStringList('backup_metadata') ?? [];

    return metadataJson
        .map((json) => BackupMetadata.fromJson(jsonDecode(json)))
        .toList();
  }

  Future<void> _saveBackupMetadata(BackupMetadata metadata) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList('backup_metadata') ?? [];
    existing.add(jsonEncode(metadata.toJson()));
    await prefs.setStringList('backup_metadata', existing);
  }

  Future<void> _cleanupOldBackups() async {
    final backups = await listBackups();
    if (backups.length <= _maxBackups) return;

    // Sort by timestamp ascending (oldest first)
    backups.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final toDelete = backups.take(backups.length - _maxBackups);
    final backupDir = await _getBackupDirectory();

    for (final backup in toDelete) {
      try {
        final file = File(p.join(backupDir.path, backup.filename));
        if (await file.exists()) {
          await file.delete();
        }
        // Also delete WAL and SHM files
        final walFile = File(p.join(backupDir.path, '${backup.filename}-wal'));
        final shmFile = File(p.join(backupDir.path, '${backup.filename}-shm'));
        if (await walFile.exists()) await walFile.delete();
        if (await shmFile.exists()) await shmFile.delete();
      } catch (e) {
        debugPrint('⚠️ Failed to delete old backup: ${backup.filename}: $e');
      }
    }

    // Update metadata list
    final prefs = await SharedPreferences.getInstance();
    final remaining = backups.skip(backups.length - _maxBackups);
    await prefs.setStringList(
      'backup_metadata',
      remaining.map((m) => jsonEncode(m.toJson())).toList(),
    );
  }

  Future<String> _calculateFileChecksum(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC JOURNALING (CRASH RECOVERY)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start a sync journal entry before a sync operation
  Future<SyncJournal> startSyncJournal({
    required String operationType,
    required List<Map<String, dynamic>> changes,
  }) async {
    final journal = SyncJournal(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      operationType: operationType,
      startedAt: DateTime.now(),
      changes: changes,
      status: SyncJournalStatus.inProgress,
    );

    await _saveSyncJournal(journal);
    return journal;
  }

  /// Mark a sync journal as completed successfully
  Future<void> completeSyncJournal(
    SyncJournal journal, {
    Map<String, int>? idMappings,
    List<Map<String, dynamic>>? conflicts,
  }) async {
    journal.completedAt = DateTime.now();
    journal.status = SyncJournalStatus.completed;
    journal.idMappings = idMappings;
    journal.conflicts = conflicts;

    await _saveSyncJournal(journal);

    // Clean up completed journal after a delay
    Future.delayed(const Duration(minutes: 5), () {
      _deleteSyncJournal(journal.id);
    });
  }

  /// Mark a sync journal as failed
  Future<void> failSyncJournal(SyncJournal journal, String error) async {
    journal.completedAt = DateTime.now();
    journal.status = SyncJournalStatus.failed;
    journal.error = error;

    await _saveSyncJournal(journal);
  }

  /// Recover from incomplete sync operations after a crash
  Future<void> _recoverFromCrash() async {
    debugPrint('🔍 Checking for incomplete sync operations...');

    final journals = await _getIncompleteSyncJournals();
    if (journals.isEmpty) {
      debugPrint('✅ No incomplete sync operations found');
      return;
    }

    debugPrint('⚠️ Found ${journals.length} incomplete sync operations');

    for (final journal in journals) {
      await _recoverSyncJournal(journal);
    }
  }

  Future<void> _recoverSyncJournal(SyncJournal journal) async {
    debugPrint('🔄 Recovering sync journal: ${journal.id}');

    // Mark all changes in this journal as needing re-sync
    // The changes are still in the sync_queue, we just need to reset their status

    try {
      if (_db != null) {
        // Use Drift to reset sync queue items
        await (_db!.update(_db!.syncQueue)
              ..where((t) =>
                  t.status.equals('syncing') | t.status.equals('in_progress')))
            .write(const SyncQueueCompanion(
          status: Value('pending'),
          retryCount: Value(0),
          errorMessage: Value('Recovered after crash'),
        ));

        debugPrint('✅ Recovered sync journal: ${journal.id}');
      }

      // Mark journal as recovered
      journal.status = SyncJournalStatus.recovered;
      journal.completedAt = DateTime.now();
      await _saveSyncJournal(journal);
    } catch (e) {
      debugPrint('❌ Failed to recover sync journal ${journal.id}: $e');
    }
  }

  Future<List<SyncJournal>> _getIncompleteSyncJournals() async {
    final prefs = await SharedPreferences.getInstance();
    final journalIds = prefs.getStringList('sync_journals') ?? [];

    final journals = <SyncJournal>[];
    for (final id in journalIds) {
      final journalJson = prefs.getString('$_journalPrefix$id');
      if (journalJson != null) {
        final journal = SyncJournal.fromJson(jsonDecode(journalJson));
        if (journal.status == SyncJournalStatus.inProgress) {
          journals.add(journal);
        }
      }
    }

    return journals;
  }

  Future<void> _saveSyncJournal(SyncJournal journal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_journalPrefix${journal.id}',
      jsonEncode(journal.toJson()),
    );

    // Update journal list
    final journalIds = prefs.getStringList('sync_journals') ?? [];
    if (!journalIds.contains(journal.id)) {
      journalIds.add(journal.id);
      await prefs.setStringList('sync_journals', journalIds);
    }
  }

  Future<void> _deleteSyncJournal(String journalId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_journalPrefix$journalId');

    final journalIds = prefs.getStringList('sync_journals') ?? [];
    journalIds.remove(journalId);
    await prefs.setStringList('sync_journals', journalIds);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA INTEGRITY VERIFICATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Verify data integrity across all tables
  Future<IntegrityReport> verifyDataIntegrity() async {
    debugPrint('🔍 Verifying data integrity...');

    final issues = <IntegrityIssue>[];
    final tablesChecked = <String>[];

    try {
      if (_db == null) {
        debugPrint('⚠️ Database not available for integrity check');
        return IntegrityReport(
          checkedAt: DateTime.now(),
          issues: [
            IntegrityIssue(
              table: 'system',
              severity: IssueSeverity.warning,
              description: 'Database not available for integrity check',
            ),
          ],
          tablesChecked: [],
        );
      }

      // 1. Check for orphaned products (products without valid store)
      tablesChecked.add('products');
      issues.addAll(await _checkOrphanedProducts());

      // 2. Check for orphaned sale items
      tablesChecked.add('sale_items');
      issues.addAll(await _checkOrphanedSaleItems());

      // 3. Check for duplicate usernames
      tablesChecked.add('users');
      issues.addAll(await _checkDuplicateUsernames());

      // 4. Check for duplicate server_ids in products
      issues.addAll(await _checkDuplicateServerIds());

      // 5. Check for sync queue issues
      tablesChecked.add('sync_queue');
      issues.addAll(await _checkSyncQueueIntegrity());

      // 6. Check for required field violations
      issues.addAll(await _checkRequiredFields());

      final report = IntegrityReport(
        checkedAt: DateTime.now(),
        issues: issues,
        tablesChecked: tablesChecked,
      );

      if (issues.isEmpty) {
        debugPrint('✅ Data integrity verified - no issues found');
      } else {
        debugPrint('⚠️ Found ${issues.length} integrity issues');
        for (final issue in issues) {
          debugPrint('   - ${issue.severity}: ${issue.description}');
        }
      }

      return report;
    } catch (e, st) {
      debugPrint('❌ Integrity check failed: $e\n$st');
      return IntegrityReport(
        checkedAt: DateTime.now(),
        issues: [
          IntegrityIssue(
            table: 'system',
            severity: IssueSeverity.critical,
            description: 'Integrity check failed: $e',
          ),
        ],
        tablesChecked: tablesChecked,
      );
    }
  }

  Future<List<IntegrityIssue>> _checkOrphanedProducts() async {
    final issues = <IntegrityIssue>[];
    try {
      // Get all store IDs
      final stores = await _db!.select(_db!.stores).get();
      final validStoreIds = stores.map((s) => s.id).toSet();

      // Get products with invalid store_id
      final products = await _db!.select(_db!.products).get();
      final orphanedCount =
          products.where((p) => !validStoreIds.contains(p.storeId)).length;

      if (orphanedCount > 0) {
        issues.add(IntegrityIssue(
          table: 'products',
          severity: IssueSeverity.warning,
          description: '$orphanedCount products reference non-existent stores',
          affectedCount: orphanedCount,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ Error checking orphaned products: $e');
    }
    return issues;
  }

  Future<List<IntegrityIssue>> _checkOrphanedSaleItems() async {
    final issues = <IntegrityIssue>[];
    try {
      // Get all sale IDs
      final sales = await _db!.select(_db!.sales).get();
      final validSaleIds = sales.map((s) => s.id).toSet();

      // Get sale items with invalid sale_id
      final saleItems = await _db!.select(_db!.saleItems).get();
      final orphanedCount =
          saleItems.where((si) => !validSaleIds.contains(si.saleId)).length;

      if (orphanedCount > 0) {
        issues.add(IntegrityIssue(
          table: 'sale_items',
          severity: IssueSeverity.error,
          description: '$orphanedCount sale items reference non-existent sales',
          affectedCount: orphanedCount,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ Error checking orphaned sale items: $e');
    }
    return issues;
  }

  Future<List<IntegrityIssue>> _checkDuplicateUsernames() async {
    final issues = <IntegrityIssue>[];
    try {
      final users = await _db!.select(_db!.users).get();
      final usernames = users.map((u) => u.username).toList();
      final uniqueUsernames = usernames.toSet();

      if (usernames.length != uniqueUsernames.length) {
        final duplicateCount = usernames.length - uniqueUsernames.length;
        issues.add(IntegrityIssue(
          table: 'users',
          severity: IssueSeverity.error,
          description: '$duplicateCount duplicate usernames found',
          affectedCount: duplicateCount,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ Error checking duplicate usernames: $e');
    }
    return issues;
  }

  Future<List<IntegrityIssue>> _checkDuplicateServerIds() async {
    final issues = <IntegrityIssue>[];
    try {
      final products = await _db!.select(_db!.products).get();
      final serverIds = products
          .where((p) => p.serverId != null)
          .map((p) => p.serverId)
          .toList();
      final uniqueServerIds = serverIds.toSet();

      if (serverIds.length != uniqueServerIds.length) {
        final duplicateCount = serverIds.length - uniqueServerIds.length;
        issues.add(IntegrityIssue(
          table: 'products',
          severity: IssueSeverity.critical,
          description: '$duplicateCount duplicate server_ids found in products',
          affectedCount: duplicateCount,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ Error checking duplicate server_ids: $e');
    }
    return issues;
  }

  Future<List<IntegrityIssue>> _checkSyncQueueIntegrity() async {
    final issues = <IntegrityIssue>[];
    try {
      final pendingItems = await (_db!.select(_db!.syncQueue)
            ..where((q) => q.status.equals('pending')))
          .get();

      // Check for items pending for over 24 hours
      final now = DateTime.now();
      final stuckItems = pendingItems.where((item) {
        final createdAt = item.createdAt;
        return now.difference(createdAt).inHours > 24;
      }).length;

      if (stuckItems > 0) {
        issues.add(IntegrityIssue(
          table: 'sync_queue',
          severity: IssueSeverity.warning,
          description: '$stuckItems sync items pending for over 24 hours',
          affectedCount: stuckItems,
        ));
      }

      // Check for items with excessive retries
      final allItems = await _db!.select(_db!.syncQueue).get();
      final excessiveRetries =
          allItems.where((item) => item.retryCount >= 10).length;

      if (excessiveRetries > 0) {
        issues.add(IntegrityIssue(
          table: 'sync_queue',
          severity: IssueSeverity.warning,
          description: '$excessiveRetries items with 10+ retry attempts',
          affectedCount: excessiveRetries,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ Error checking sync queue integrity: $e');
    }
    return issues;
  }

  Future<List<IntegrityIssue>> _checkRequiredFields() async {
    final issues = <IntegrityIssue>[];

    try {
      // Check products without names
      final products = await _db!.select(_db!.products).get();
      final productsWithoutNames = products.where((p) => p.name.isEmpty).length;

      if (productsWithoutNames > 0) {
        issues.add(IntegrityIssue(
          table: 'products',
          severity: IssueSeverity.error,
          description: '$productsWithoutNames products with missing names',
          affectedCount: productsWithoutNames,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ Error checking product names: $e');
    }

    try {
      // Check users without usernames
      final users = await _db!.select(_db!.users).get();
      final usersWithoutUsernames =
          users.where((u) => u.username.isEmpty).length;

      if (usersWithoutUsernames > 0) {
        issues.add(IntegrityIssue(
          table: 'users',
          severity: IssueSeverity.critical,
          description: '$usersWithoutUsernames users with missing usernames',
          affectedCount: usersWithoutUsernames,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ Error checking usernames: $e');
    }

    return issues;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFLICT PRESERVATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Preserve a conflict for later resolution (never lose data)
  Future<void> preserveConflict({
    required String resourceType,
    required String resourceId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
  }) async {
    try {
      if (_db != null) {
        await _db!
            .into(_db!.syncConflicts)
            .insert(SyncConflictsCompanion.insert(
              resourceType: resourceType,
              resourceId: resourceId,
              localDataJson: jsonEncode(localData),
              serverDataJson: jsonEncode(serverData),
            ));
        debugPrint('📋 Preserved conflict for $resourceType/$resourceId');
      } else {
        // Fallback: store in SharedPreferences
        await _preserveConflictFallback(
          resourceType: resourceType,
          resourceId: resourceId,
          localData: localData,
          serverData: serverData,
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to preserve conflict: $e');
      await _preserveConflictFallback(
        resourceType: resourceType,
        resourceId: resourceId,
        localData: localData,
        serverData: serverData,
      );
    }
  }

  Future<void> _preserveConflictFallback({
    required String resourceType,
    required String resourceId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final conflicts = prefs.getStringList('preserved_conflicts') ?? [];
    conflicts.add(jsonEncode({
      'resource_type': resourceType,
      'resource_id': resourceId,
      'local_data': localData,
      'server_data': serverData,
      'created_at': DateTime.now().toIso8601String(),
    }));
    await prefs.setStringList('preserved_conflicts', conflicts);
  }

  /// Get all unresolved conflicts
  Future<List<SyncConflict>> getUnresolvedConflicts() async {
    try {
      if (_db != null) {
        return await (_db!.select(_db!.syncConflicts)
              ..where((c) => c.resolution.isNull())
              ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
            .get();
      }
      return [];
    } catch (e) {
      debugPrint('❌ Failed to get conflicts: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UNINSTALL PROTECTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export critical data to external storage before uninstall
  Future<ExportResult> exportForUninstallProtection() async {
    try {
      debugPrint('📤 Exporting data for uninstall protection...');

      if (_db == null) {
        return ExportResult(success: false, error: 'Database not available');
      }

      final exportDir = await _getBackupDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportPath =
          p.join(exportDir.path, 'uninstall_protection_$timestamp.json');

      // Export all critical data using Drift
      final exportData = <String, dynamic>{
        'exported_at': DateTime.now().toIso8601String(),
        'version': '1.0',
      };

      // Export unsynced data (most critical)
      final pendingSync = await (_db!.select(_db!.syncQueue)
            ..where((q) => q.status.equals('pending')))
          .get();
      exportData['pending_sync'] = pendingSync
          .map((s) => {
                'id': s.id,
                'client_temp_id': s.clientTempId,
                'resource_type': s.resourceType,
                'operation': s.operation,
                'entity_id': s.entityId,
                'payload_json': s.payloadJson,
                'created_at': s.createdAt.toIso8601String(),
              })
          .toList();

      // Export sync conflicts
      final conflicts = await _db!.select(_db!.syncConflicts).get();
      exportData['sync_conflicts'] = conflicts
          .map((c) => {
                'id': c.id,
                'resource_type': c.resourceType,
                'resource_id': c.resourceId,
                'local_data_json': c.localDataJson,
                'server_data_json': c.serverDataJson,
                'resolution': c.resolution,
                'created_at': c.createdAt.toIso8601String(),
              })
          .toList();

      // Export local-only sales (not synced yet)
      final unsyncedSales = await (_db!.select(_db!.sales)
            ..where((s) => s.serverId.isNull()))
          .get();
      exportData['unsynced_sales'] = unsyncedSales
          .map((s) => {
                'id': s.id,
                'client_id': s.clientId,
                'transaction_number': s.transactionNumber,
                'user_id': s.userId,
                'store_id': s.storeId,
                'total_amount': s.totalAmount,
                'payment_method': s.paymentMethod,
                'payment_reference': s.paymentReference,
                'status': s.status,
                'created_at': s.createdAt.toIso8601String(),
              })
          .toList();

      // Export sync metadata
      final syncMeta = await _db!.select(_db!.syncMeta).get();
      exportData['sync_meta'] = syncMeta
          .map((m) => {
                'key': m.key,
                'value': m.value,
              })
          .toList();

      // Write to external storage
      final exportFile = File(exportPath);
      await exportFile.writeAsString(jsonEncode(exportData));

      // Store export location in secure storage (survives uninstall on some devices)
      await _secureStorage.write(
        key: 'last_export_path',
        value: exportPath,
      );
      await _secureStorage.write(
        key: 'last_export_time',
        value: DateTime.now().toIso8601String(),
      );

      debugPrint('✅ Export completed: $exportPath');
      return ExportResult(success: true, exportPath: exportPath);
    } catch (e, st) {
      debugPrint('❌ Export failed: $e\n$st');
      return ExportResult(success: false, error: e.toString());
    }
  }

  /// Import data after reinstall
  Future<ImportResult> importAfterReinstall() async {
    try {
      debugPrint('📥 Checking for data to import after reinstall...');

      final exportPath = await _secureStorage.read(key: 'last_export_path');
      if (exportPath == null) {
        // Try to find exports in backup directory
        final backupDir = await _getBackupDirectory();
        final files = await backupDir.list().toList();
        final exportFiles = files
            .whereType<File>()
            .where((f) => f.path.contains('uninstall_protection_'))
            .toList();

        if (exportFiles.isEmpty) {
          debugPrint('ℹ️ No export files found');
          return ImportResult(success: false, error: 'No export data found');
        }

        // Use most recent export
        exportFiles.sort((a, b) => b.path.compareTo(a.path));
        return _importFromFile(exportFiles.first.path);
      }

      return _importFromFile(exportPath);
    } catch (e, st) {
      debugPrint('❌ Import failed: $e\n$st');
      return ImportResult(success: false, error: e.toString());
    }
  }

  Future<ImportResult> _importFromFile(String exportPath) async {
    try {
      if (_db == null) {
        return ImportResult(success: false, error: 'Database not available');
      }

      final exportFile = File(exportPath);
      if (!await exportFile.exists()) {
        return ImportResult(success: false, error: 'Export file not found');
      }

      final contents = await exportFile.readAsString();
      final exportData = jsonDecode(contents) as Map<String, dynamic>;

      int importedCount = 0;

      // Import sync queue items first (critical unsynced changes)
      final pendingSync = exportData['pending_sync'] as List? ?? [];
      for (final item in pendingSync) {
        try {
          await _db!.into(_db!.syncQueue).insert(
                SyncQueueCompanion.insert(
                  clientTempId: Value(item['client_temp_id'] as String?),
                  resourceType: item['resource_type'] as String,
                  operation: item['operation'] as String,
                  entityId: Value(item['entity_id'] as String?),
                  payloadJson: item['payload_json'] as String,
                ),
                mode: InsertMode.insertOrIgnore,
              );
          importedCount++;
        } catch (e) {
          debugPrint('⚠️ Failed to import sync queue item: $e');
        }
      }

      // Import sync conflicts (preserved conflicts)
      final conflicts = exportData['sync_conflicts'] as List? ?? [];
      for (final conflict in conflicts) {
        try {
          await _db!.into(_db!.syncConflicts).insert(
                SyncConflictsCompanion.insert(
                  resourceType: conflict['resource_type'] as String,
                  resourceId: conflict['resource_id'] as String,
                  localDataJson: conflict['local_data_json'] as String,
                  serverDataJson: conflict['server_data_json'] as String,
                  resolution: Value(conflict['resolution'] as String?),
                ),
                mode: InsertMode.insertOrIgnore,
              );
          importedCount++;
        } catch (e) {
          debugPrint('⚠️ Failed to import conflict: $e');
        }
      }

      // Import sync metadata
      final syncMeta = exportData['sync_meta'] as List? ?? [];
      for (final meta in syncMeta) {
        try {
          await _db!.into(_db!.syncMeta).insert(
                SyncMetaCompanion.insert(
                  key: meta['key'] as String,
                  value: Value(meta['value'] as String?),
                ),
                mode: InsertMode.insertOrReplace,
              );
        } catch (e) {
          debugPrint('⚠️ Failed to import sync meta: $e');
        }
      }

      debugPrint('✅ Import completed: $importedCount items');
      return ImportResult(
        success: true,
        importedCount: importedCount,
        sourceFile: exportPath,
      );
    } catch (e, st) {
      debugPrint('❌ Import from file failed: $e\n$st');
      return ImportResult(success: false, error: e.toString());
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATABASE OPTIMIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable WAL mode for better crash recovery
  Future<void> enableWALMode() async {
    try {
      if (_db != null) {
        // Use query-style PRAGMA calls on Android (they return a row)
        await _db!.customSelect('PRAGMA journal_mode=WAL').getSingle();
        await _db!.customSelect('PRAGMA synchronous=NORMAL').getSingle();
        await _db!.customSelect('PRAGMA temp_store=MEMORY').getSingle();
        await _db!
            .customSelect('PRAGMA mmap_size=268435456')
            .getSingle(); // 256MB memory-mapped I/O
        debugPrint('✅ WAL mode enabled');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to enable WAL mode: $e');
    }
  }

  /// Checkpoint WAL file to main database
  Future<void> checkpointWAL() async {
    try {
      if (_db != null) {
        // PRAGMA wal_checkpoint returns a result row on some platforms
        final chk = await _db!
            .customSelect('PRAGMA wal_checkpoint(TRUNCATE)')
            .getSingleOrNull();
        if (chk == null) debugPrint('PRAGMA wal_checkpoint returned no rows');
        debugPrint('✅ WAL checkpoint completed');
      }
    } catch (e) {
      debugPrint('⚠️ WAL checkpoint failed: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

class BackupMetadata {
  final String filename;
  final DateTime timestamp;
  final String reason;
  final String checksum;
  final int sizeBytes;

  BackupMetadata({
    required this.filename,
    required this.timestamp,
    required this.reason,
    required this.checksum,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'timestamp': timestamp.toIso8601String(),
        'reason': reason,
        'checksum': checksum,
        'sizeBytes': sizeBytes,
      };

  factory BackupMetadata.fromJson(Map<String, dynamic> json) => BackupMetadata(
        filename: json['filename'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        reason: json['reason'] as String,
        checksum: json['checksum'] as String,
        sizeBytes: json['sizeBytes'] as int,
      );
}

class BackupResult {
  final bool success;
  final String? backupPath;
  final String? error;
  final BackupMetadata? metadata;

  BackupResult({
    required this.success,
    this.backupPath,
    this.error,
    this.metadata,
  });
}

class RestoreResult {
  final bool success;
  final String? error;
  final BackupMetadata? restoredFrom;

  RestoreResult({
    required this.success,
    this.error,
    this.restoredFrom,
  });
}

class ExportResult {
  final bool success;
  final String? exportPath;
  final String? error;

  ExportResult({required this.success, this.exportPath, this.error});
}

class ImportResult {
  final bool success;
  final String? error;
  final int? importedCount;
  final String? sourceFile;

  ImportResult({
    required this.success,
    this.error,
    this.importedCount,
    this.sourceFile,
  });
}

enum SyncJournalStatus { inProgress, completed, failed, recovered }

class SyncJournal {
  final String id;
  final String operationType;
  final DateTime startedAt;
  final List<Map<String, dynamic>> changes;
  SyncJournalStatus status;
  DateTime? completedAt;
  Map<String, int>? idMappings;
  List<Map<String, dynamic>>? conflicts;
  String? error;

  SyncJournal({
    required this.id,
    required this.operationType,
    required this.startedAt,
    required this.changes,
    required this.status,
    this.completedAt,
    this.idMappings,
    this.conflicts,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'operationType': operationType,
        'startedAt': startedAt.toIso8601String(),
        'changes': changes,
        'status': status.name,
        'completedAt': completedAt?.toIso8601String(),
        'idMappings': idMappings,
        'conflicts': conflicts,
        'error': error,
      };

  factory SyncJournal.fromJson(Map<String, dynamic> json) => SyncJournal(
        id: json['id'] as String,
        operationType: json['operationType'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        changes: (json['changes'] as List).cast<Map<String, dynamic>>(),
        status: SyncJournalStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => SyncJournalStatus.failed,
        ),
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        idMappings: (json['idMappings'] as Map?)?.cast<String, int>(),
        conflicts: (json['conflicts'] as List?)?.cast<Map<String, dynamic>>(),
        error: json['error'] as String?,
      );
}

enum IssueSeverity { info, warning, error, critical }

class IntegrityIssue {
  final String table;
  final IssueSeverity severity;
  final String description;
  final int? affectedCount;

  IntegrityIssue({
    required this.table,
    required this.severity,
    required this.description,
    this.affectedCount,
  });
}

class IntegrityReport {
  final DateTime checkedAt;
  final List<IntegrityIssue> issues;
  final List<String> tablesChecked;

  IntegrityReport({
    required this.checkedAt,
    required this.issues,
    required this.tablesChecked,
  });

  bool get hasIssues => issues.isNotEmpty;
  bool get hasCriticalIssues =>
      issues.any((i) => i.severity == IssueSeverity.critical);
}
