import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/data_protection_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Mock path provider for testing
class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getExternalStoragePath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataProtectionService service;

  setUp(() async {
    // Setup mock path provider
    PathProviderPlatform.instance = MockPathProviderPlatform();

    // Clear shared preferences
    SharedPreferences.setMockInitialValues({});

    service = DataProtectionService();
  });

  tearDown(() async {
    // Clean up test files
    try {
      final tempDir = Directory.systemTemp;
      final testFiles = tempDir.listSync().where((f) =>
          f.path.contains('pos_backup_') ||
          f.path.contains('sync_journal_') ||
          f.path.contains('app.sqlite'));
      for (final file in testFiles) {
        if (file is File) {
          await file.delete();
        }
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  });

  group('DataProtectionService - Initialization', () {
    test('initializes successfully', () async {
      await service.initialize();
      expect(service, isNotNull);
    });

    test('shutdown completes without error', () async {
      await service.initialize();
      await expectLater(service.shutdown(), completes);
    });
  });

  group('DataProtectionService - Backup Operations', () {
    test('creates backup successfully when database exists', () async {
      await service.initialize();

      // Create a mock database file
      final tempDir = Directory.systemTemp;
      final dbFile = File('${tempDir.path}/app.sqlite');
      await dbFile.writeAsString('mock database content');

      final result = await service.createBackup(reason: 'test');

      expect(result.success, isTrue);
      expect(result.backupPath, isNotNull);
      expect(result.metadata, isNotNull);
      expect(result.metadata?.reason, 'test');
    });

    test('backup fails gracefully when database does not exist', () async {
      await service.initialize();

      final result = await service.createBackup(reason: 'test');

      expect(result.success, isFalse);
      expect(result.error, contains('Source database not found'));
    });

    test('lists backups correctly', () async {
      await service.initialize();

      // Create a mock database file
      final tempDir = Directory.systemTemp;
      final dbFile = File('${tempDir.path}/app.sqlite');
      await dbFile.writeAsString('mock database content');

      // Create multiple backups
      await service.createBackup(reason: 'test1');
      await service.createBackup(reason: 'test2');

      final backups = await service.listBackups();

      expect(backups.length, greaterThanOrEqualTo(2));
      expect(backups.any((b) => b.reason == 'test1'), isTrue);
      expect(backups.any((b) => b.reason == 'test2'), isTrue);
    });

    test('cleans up old backups when limit exceeded', () async {
      await service.initialize();

      final tempDir = Directory.systemTemp;
      final dbFile = File('${tempDir.path}/app.sqlite');
      await dbFile.writeAsString('mock database content');

      // Create more than max backups (5)
      for (int i = 0; i < 7; i++) {
        await service.createBackup(reason: 'test$i');
        await Future.delayed(
            const Duration(milliseconds: 100)); // Ensure different timestamps
      }

      final backups = await service.listBackups();

      // Should keep only the 5 most recent
      expect(backups.length, lessThanOrEqualTo(5));
    });
  });

  group('DataProtectionService - Restore Operations', () {
    test('restore requires valid backup file', () async {
      await service.initialize();

      final fakeMetadata = BackupMetadata(
        filename: 'nonexistent.db',
        timestamp: DateTime.now(),
        reason: 'test',
        checksum: 'fakechecksum',
        sizeBytes: 100,
      );

      final result = await service.restoreFromBackup(fakeMetadata);

      expect(result.success, isFalse);
      expect(result.error, contains('not found'));
    });

    test('restoreFromLatestBackup fails when no backups exist', () async {
      await service.initialize();

      final result = await service.restoreFromLatestBackup();

      expect(result.success, isFalse);
      expect(result.error, contains('No backups available'));
    });
  });

  group('DataProtectionService - Sync Journaling', () {
    test('starts sync journal successfully', () async {
      await service.initialize();

      final changes = [
        {'id': 1, 'action': 'create'},
        {'id': 2, 'action': 'update'},
      ];

      final journal = await service.startSyncJournal(
        operationType: 'test_operation',
        changes: changes,
      );

      expect(journal.id, isNotEmpty);
      expect(journal.operationType, 'test_operation');
      expect(journal.changes.length, 2);
      expect(journal.status, SyncJournalStatus.inProgress);
    });

    test('completes sync journal successfully', () async {
      await service.initialize();

      final changes = [
        {'id': 1, 'action': 'create'}
      ];
      final journal = await service.startSyncJournal(
        operationType: 'test_operation',
        changes: changes,
      );

      await service.completeSyncJournal(
        journal,
        idMappings: {'1': 100},
        conflicts: [],
      );

      expect(journal.status, SyncJournalStatus.completed);
      expect(journal.completedAt, isNotNull);
      expect(journal.idMappings, isNotNull);
    });

    test('fails sync journal with error message', () async {
      await service.initialize();

      final changes = [
        {'id': 1, 'action': 'create'}
      ];
      final journal = await service.startSyncJournal(
        operationType: 'test_operation',
        changes: changes,
      );

      await service.failSyncJournal(journal, 'Test error');

      expect(journal.status, SyncJournalStatus.failed);
      expect(journal.error, 'Test error');
      expect(journal.completedAt, isNotNull);
    });
  });

  group('DataProtectionService - Data Integrity', () {
    test('verifyDataIntegrity returns report without errors', () async {
      await service.initialize();

      // Create a mock database file
      final tempDir = Directory.systemTemp;
      final dbFile = File('${tempDir.path}/app.sqlite');
      await dbFile.writeAsString('mock database content');

      final report = await service.verifyDataIntegrity();

      expect(report, isNotNull);
      expect(report.checkedAt, isNotNull);
      expect(report.tablesChecked, isNotEmpty);
    });

    test('integrity report has proper structure', () async {
      await service.initialize();

      final tempDir = Directory.systemTemp;
      final dbFile = File('${tempDir.path}/app.sqlite');
      await dbFile.writeAsString('mock database content');

      final report = await service.verifyDataIntegrity();

      expect(report.checkedAt, isA<DateTime>());
      expect(report.issues, isA<List<IntegrityIssue>>());
      expect(report.tablesChecked, isA<List<String>>());
      expect(report.hasIssues, isA<bool>());
      expect(report.hasCriticalIssues, isA<bool>());
    });
  });

  group('DataProtectionService - Conflict Preservation', () {
    test('preserves conflict successfully', () async {
      await service.initialize();

      // Create mock database
      final tempDir = Directory.systemTemp;
      final dbFile = File('${tempDir.path}/app.sqlite');
      await dbFile.writeAsString('mock database content');

      await expectLater(
        service.preserveConflict(
          resourceType: 'product',
          resourceId: '123',
          localData: {'name': 'Local Product'},
          serverData: {'name': 'Server Product'},
        ),
        completes,
      );
    });

    test('gets unresolved conflicts', () async {
      await service.initialize();

      final tempDir = Directory.systemTemp;
      final dbFile = File('${tempDir.path}/app.sqlite');
      await dbFile.writeAsString('mock database content');

      final conflicts = await service.getUnresolvedConflicts();

      expect(conflicts, isA<List<Map<String, dynamic>>>());
    });
  });

  group('DataProtectionService - Export/Import', () {
    test('exportForUninstallProtection creates export file', () async {
      await service.initialize();

      final tempDir = Directory.systemTemp;
      final dbFile = File('${tempDir.path}/app.sqlite');
      await dbFile.writeAsString('mock database content');

      final result = await service.exportForUninstallProtection();

      expect(result.success, isTrue);
      expect(result.exportPath, isNotNull);
      if (result.exportPath != null) {
        expect(File(result.exportPath!).existsSync(), isTrue);
      }
    });

    test('importAfterReinstall fails when no export exists', () async {
      await service.initialize();

      final result = await service.importAfterReinstall();

      expect(result.success, isFalse);
    });
  });

  group('DataProtectionService - WAL Mode', () {
    test('enableWALMode completes without error', () async {
      final tempDir = Directory.systemTemp;
      final dbFile = File('${tempDir.path}/app.sqlite');
      await dbFile.writeAsString('mock database content');

      await expectLater(service.enableWALMode(), completes);
    });

    test('checkpointWAL completes without error', () async {
      final tempDir = Directory.systemTemp;
      final dbFile = File('${tempDir.path}/app.sqlite');
      await dbFile.writeAsString('mock database content');

      await expectLater(service.checkpointWAL(), completes);
    });
  });

  group('BackupMetadata', () {
    test('serializes to JSON correctly', () {
      final metadata = BackupMetadata(
        filename: 'test_backup.db',
        timestamp: DateTime(2026, 1, 1, 12, 0, 0),
        reason: 'test',
        checksum: 'abc123',
        sizeBytes: 1024,
      );

      final json = metadata.toJson();

      expect(json['filename'], 'test_backup.db');
      expect(json['reason'], 'test');
      expect(json['checksum'], 'abc123');
      expect(json['sizeBytes'], 1024);
      expect(json['timestamp'], isA<String>());
    });

    test('deserializes from JSON correctly', () {
      final json = {
        'filename': 'test_backup.db',
        'timestamp': '2026-01-01T12:00:00.000',
        'reason': 'test',
        'checksum': 'abc123',
        'sizeBytes': 1024,
      };

      final metadata = BackupMetadata.fromJson(json);

      expect(metadata.filename, 'test_backup.db');
      expect(metadata.reason, 'test');
      expect(metadata.checksum, 'abc123');
      expect(metadata.sizeBytes, 1024);
      expect(metadata.timestamp, DateTime(2026, 1, 1, 12, 0, 0));
    });
  });

  group('BackupResult', () {
    test('creates success result correctly', () {
      final result = BackupResult(
        success: true,
        backupPath: '/path/to/backup.db',
      );

      expect(result.success, isTrue);
      expect(result.backupPath, '/path/to/backup.db');
      expect(result.error, isNull);
    });

    test('creates failure result correctly', () {
      final result = BackupResult(
        success: false,
        error: 'Backup failed',
      );

      expect(result.success, isFalse);
      expect(result.error, 'Backup failed');
      expect(result.backupPath, isNull);
    });
  });

  group('SyncJournal', () {
    test('serializes to JSON correctly', () {
      final journal = SyncJournal(
        id: 'test_123',
        operationType: 'push',
        startedAt: DateTime(2026, 1, 1, 12, 0, 0),
        changes: [
          {'id': 1, 'action': 'create'}
        ],
        status: SyncJournalStatus.completed,
      );

      final json = journal.toJson();

      expect(json['id'], 'test_123');
      expect(json['operationType'], 'push');
      expect(json['status'], 'completed');
      expect(json['changes'], isA<List>());
    });

    test('deserializes from JSON correctly', () {
      final json = {
        'id': 'test_123',
        'operationType': 'push',
        'startedAt': '2026-01-01T12:00:00.000',
        'changes': [
          {'id': 1, 'action': 'create'}
        ],
        'status': 'completed',
      };

      final journal = SyncJournal.fromJson(json);

      expect(journal.id, 'test_123');
      expect(journal.operationType, 'push');
      expect(journal.status, SyncJournalStatus.completed);
      expect(journal.changes.length, 1);
    });
  });

  group('IntegrityReport', () {
    test('detects issues correctly', () {
      final issueReport = IntegrityReport(
        checkedAt: DateTime.now(),
        issues: [
          IntegrityIssue(
            table: 'products',
            severity: IssueSeverity.warning,
            description: 'Test issue',
          ),
        ],
        tablesChecked: ['products', 'users'],
      );

      expect(issueReport.hasIssues, isTrue);
      expect(issueReport.hasCriticalIssues, isFalse);
    });

    test('detects critical issues correctly', () {
      final criticalReport = IntegrityReport(
        checkedAt: DateTime.now(),
        issues: [
          IntegrityIssue(
            table: 'users',
            severity: IssueSeverity.critical,
            description: 'Critical issue',
          ),
        ],
        tablesChecked: ['users'],
      );

      expect(criticalReport.hasIssues, isTrue);
      expect(criticalReport.hasCriticalIssues, isTrue);
    });

    test('reports no issues correctly', () {
      final cleanReport = IntegrityReport(
        checkedAt: DateTime.now(),
        issues: [],
        tablesChecked: ['products', 'users', 'stores'],
      );

      expect(cleanReport.hasIssues, isFalse);
      expect(cleanReport.hasCriticalIssues, isFalse);
    });
  });
}
