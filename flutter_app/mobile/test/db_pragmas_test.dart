import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/db/app_database.dart';
import 'dart:io';

// Initialize sqflite ffi in desktop test environments so on-disk DBs can be opened
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('Database PRAGMA configuration', () {
    test('PRAGMA settings are automatically configured on database opening',
        () async {
      // Note: In-memory databases don't support WAL mode and will report 'memory' journal mode.
      // For full WAL testing, use an on-disk database with AppDatabase.openWithPath().
      final db = AppDatabase.inMemory();

      // PRAGMA configuration happens automatically during database opening.
      // The deprecated configureDatabaseForConcurrency function no longer does anything.

      // Check that the database status can be queried without errors
      final info = await getDatabaseLockStatus(db);

      expect(info['is_healthy'], isTrue,
          reason: 'Database health check should succeed');

      final journal = (info['journal_mode'] ?? '').toString().toLowerCase();
      // In-memory DBs report 'memory' journal mode; on-disk DB should report 'wal'. Accept either.
      expect(journal.contains('wal') || journal.contains('memory'), isTrue,
          reason:
              'Expected journal_mode to include "wal" or "memory", got: ${info['journal_mode']}');

      await db.close();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('On-disk database enables WAL mode automatically', () async {
      // Create a temporary on-disk database to verify WAL mode
      final tempDir = Directory.systemTemp.createTempSync('db_pragma_test');
      final dbPath = '${tempDir.path}/test.sqlite';

      try {
        // Ensure ffi database factory is registered when running on desktop tests
        try {
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;
        } catch (_) {}

        final db = await AppDatabase.openWithPath(dbPath);

        // Check WAL mode is enabled for on-disk databases
        final info = await getDatabaseLockStatus(db);

        expect(info['is_healthy'], isTrue,
            reason: 'On-disk database health check should succeed');

        final journal = (info['journal_mode'] ?? '').toString().toLowerCase();
        // On-disk databases should report 'wal' mode
        expect(journal.contains('wal'), isTrue,
            reason:
                'Expected on-disk database to use WAL mode, got: ${info['journal_mode']}');

        await db.close();
      } finally {
        // Clean up temp directory
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
