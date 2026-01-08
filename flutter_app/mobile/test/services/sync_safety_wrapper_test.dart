import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/sync_safety_wrapper.dart';
import 'package:mobile/services/data_protection_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:io';

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

  late DataProtectionService dataProtection;
  late SyncSafetyWrapper syncSafety;

  setUp(() async {
    PathProviderPlatform.instance = MockPathProviderPlatform();
    dataProtection = DataProtectionService();
    await dataProtection.initialize();
    syncSafety = SyncSafetyWrapper(dataProtection);
  });

  tearDown(() async {
    await dataProtection.shutdown();
  });

  group('SyncSafetyWrapper - Safe Sync Execution', () {
    test('executeSafeSync succeeds on first try', () async {
      int callCount = 0;

      final result = await syncSafety.executeSafeSync(
        operationId: 'test_op_1',
        changes: [
          {'id': 1, 'action': 'create'}
        ],
        syncOperation: () async {
          callCount++;
          return {'success': true};
        },
      );

      expect(result.success, isTrue);
      expect(result.attempts, 1);
      expect(callCount, 1);
      expect(result.data, {'success': true});
    });

    test('executeSafeSync retries on failure', () async {
      int callCount = 0;

      final result = await syncSafety.executeSafeSync(
        operationId: 'test_op_2',
        changes: [
          {'id': 1, 'action': 'create'}
        ],
        syncOperation: () async {
          callCount++;
          if (callCount < 3) {
            throw Exception('Simulated failure');
          }
          return {'success': true};
        },
        allowRetry: true,
      );

      expect(result.success, isTrue);
      expect(result.attempts, 3);
      expect(callCount, 3);
    });

    test('executeSafeSync fails after max retries', () async {
      int callCount = 0;

      final result = await syncSafety.executeSafeSync(
        operationId: 'test_op_3',
        changes: [
          {'id': 1, 'action': 'create'}
        ],
        syncOperation: () async {
          callCount++;
          throw Exception('Persistent failure');
        },
        allowRetry: true,
      );

      expect(result.success, isFalse);
      expect(result.attempts, greaterThan(0));
      expect(result.error, isNotNull);
      expect(callCount, greaterThan(1));
    });

    test('executeSafeSync respects idempotency', () async {
      int callCount = 0;

      // First execution
      await syncSafety.executeSafeSync(
        operationId: 'test_op_idempotent',
        changes: [
          {'id': 1, 'action': 'create'}
        ],
        syncOperation: () async {
          callCount++;
          return {'success': true};
        },
      );

      // Second execution with same operationId
      final result = await syncSafety.executeSafeSync(
        operationId: 'test_op_idempotent',
        changes: [
          {'id': 1, 'action': 'create'}
        ],
        syncOperation: () async {
          callCount++;
          return {'success': true};
        },
      );

      expect(result.success, isTrue);
      expect(result.skipped, isTrue);
      expect(callCount, 1); // Should not execute twice
    });
  });

  group('SyncSafetyWrapper - Batch Sync with Checkpoints', () {
    test('executeBatchSyncWithCheckpoints processes all items', () async {
      final items = List.generate(
        10,
        (i) => SyncBatchItem<Map<String, int>>(
          id: 'item_$i',
          data: {'value': i},
        ),
      );

      int processedCount = 0;

      final result =
          await syncSafety.executeBatchSyncWithCheckpoints<Map<String, int>>(
        batchId: 'batch_push_1',
        items: items,
        processItem: (item) async {
          processedCount++;
          return {'count': processedCount};
        },
        checkpointInterval: 3,
      );

      expect(result.isFullySuccessful, isTrue);
      expect(result.totalItems, 10);
      expect(result.successCount, 10);
      expect(result.failureCount, 0);
      expect(processedCount, 10);
    });

    test('executeBatchSyncWithCheckpoints handles partial failures', () async {
      final items = List.generate(
        5,
        (i) => SyncBatchItem<Map<String, int>>(
          id: 'item_$i',
          data: {'value': i},
        ),
      );

      final result =
          await syncSafety.executeBatchSyncWithCheckpoints<Map<String, int>>(
        batchId: 'batch_push_2',
        items: items,
        processItem: (item) async {
          final index = int.parse(item.id.split('_')[1]);
          if (index == 2) {
            throw Exception('Simulated failure for item 2');
          }
          return {'index': index};
        },
        checkpointInterval: 2,
      );

      expect(result.totalItems, 5);
      expect(result.successCount, 4);
      expect(result.failureCount, 1);
      expect(result.results.any((r) => r.error != null), isTrue);
    });
  });

  group('SyncSafetyWrapper - Conflict Resolution', () {
    test('handleConflict with preferLocal strategy', () async {
      final resolution = await syncSafety.handleConflict(
        resourceType: 'product',
        resourceId: '123',
        localData: {'name': 'Local Product', 'price': 100},
        serverData: {'name': 'Server Product', 'price': 150},
        strategy: ConflictResolutionStrategy.preferLocal,
      );

      expect(resolution.strategy, ConflictResolutionStrategy.preferLocal);
      expect(resolution.resolvedData, {'name': 'Local Product', 'price': 100});
      expect(resolution.preserved, isTrue);
    });

    test('handleConflict with preferServer strategy', () async {
      final resolution = await syncSafety.handleConflict(
        resourceType: 'product',
        resourceId: '123',
        localData: {'name': 'Local Product', 'price': 100},
        serverData: {'name': 'Server Product', 'price': 150},
        strategy: ConflictResolutionStrategy.preferServer,
      );

      expect(resolution.strategy, ConflictResolutionStrategy.preferServer);
      expect(resolution.resolvedData, {'name': 'Server Product', 'price': 150});
      expect(resolution.preserved, isTrue);
    });

    test('handleConflict with preferNewest strategy', () async {
      final now = DateTime.now();
      final older = now.subtract(const Duration(hours: 1));

      final resolution = await syncSafety.handleConflict(
        resourceType: 'product',
        resourceId: '123',
        localData: {
          'name': 'Local Product',
          'last_updated_at': now.toIso8601String()
        },
        serverData: {
          'name': 'Server Product',
          'last_updated_at': older.toIso8601String()
        },
        strategy: ConflictResolutionStrategy.preferNewest,
      );

      expect(resolution.strategy, ConflictResolutionStrategy.preferNewest);
      expect(resolution.resolvedData['name'], 'Local Product');
      expect(resolution.preserved, isTrue);
    });

    test('handleConflict with merge strategy', () async {
      final resolution = await syncSafety.handleConflict(
        resourceType: 'product',
        resourceId: '123',
        localData: {'name': 'Local Product', 'price': 100},
        serverData: {'name': 'Server Product', 'stock': 50},
        strategy: ConflictResolutionStrategy.merge,
      );

      expect(resolution.strategy, ConflictResolutionStrategy.merge);
      expect(resolution.resolvedData['name'],
          'Local Product'); // Local wins for duplicates
      expect(resolution.resolvedData['price'], 100);
      expect(resolution.resolvedData['stock'], 50);
      expect(resolution.preserved, isTrue);
    });

    test('handleConflict with preserveBoth strategy', () async {
      final resolution = await syncSafety.handleConflict(
        resourceType: 'product',
        resourceId: '123',
        localData: {'name': 'Local Product', 'price': 100},
        serverData: {'name': 'Server Product', 'price': 150},
        strategy: ConflictResolutionStrategy.preserveBoth,
      );

      expect(resolution.strategy, ConflictResolutionStrategy.preserveBoth);
      expect(resolution.requiresManualResolution, isTrue);
    });
  });

  group('SafeSyncResult', () {
    test('creates success result correctly', () {
      final result = SafeSyncResult(
        success: true,
        data: {'result': 'success'},
        attempts: 1,
      );

      expect(result.success, isTrue);
      expect(result.attempts, 1);
      expect(result.skipped, isFalse);
      expect(result.error, isNull);
    });

    test('creates failure result correctly', () {
      final result = SafeSyncResult(
        success: false,
        error: Exception('Network timeout'),
        attempts: 3,
        message: 'Operation failed',
      );

      expect(result.success, isFalse);
      expect(result.attempts, 3);
      expect(result.error, isA<Exception>());
    });

    test('creates skipped result correctly', () {
      final result = SafeSyncResult(
        success: true,
        skipped: true,
        message: 'Already processed',
      );

      expect(result.success, isTrue);
      expect(result.skipped, isTrue);
    });
  });

  group('BatchSyncResult', () {
    test('isFullySuccessful when all items succeed', () {
      final itemResults = [
        SyncBatchItemResult(
          item: SyncBatchItem(id: 'item_1', data: {}),
          success: true,
          result: {},
        ),
        SyncBatchItemResult(
          item: SyncBatchItem(id: 'item_2', data: {}),
          success: true,
          result: {},
        ),
      ];

      final result = BatchSyncResult(
        batchId: 'batch_1',
        totalItems: 2,
        successCount: 2,
        failureCount: 0,
        results: itemResults,
      );

      expect(result.isFullySuccessful, isTrue);
      expect(result.isPartiallySuccessful, isFalse);
      expect(result.isTotalFailure, isFalse);
    });

    test('isPartiallySuccessful when some items fail', () {
      final itemResults = [
        SyncBatchItemResult(
          item: SyncBatchItem(id: 'item_1', data: {}),
          success: true,
          result: {},
        ),
        SyncBatchItemResult(
          item: SyncBatchItem(id: 'item_2', data: {}),
          success: false,
          error: 'Failed',
        ),
      ];

      final result = BatchSyncResult(
        batchId: 'batch_2',
        totalItems: 2,
        successCount: 1,
        failureCount: 1,
        results: itemResults,
      );

      expect(result.isFullySuccessful, isFalse);
      expect(result.isPartiallySuccessful, isTrue);
      expect(result.isTotalFailure, isFalse);
    });

    test('isTotalFailure when all items fail', () {
      final itemResults = [
        SyncBatchItemResult(
          item: SyncBatchItem(id: 'item_1', data: {}),
          success: false,
          error: 'Failed',
        ),
        SyncBatchItemResult(
          item: SyncBatchItem(id: 'item_2', data: {}),
          success: false,
          error: 'Failed',
        ),
      ];

      final result = BatchSyncResult(
        batchId: 'batch_3',
        totalItems: 2,
        successCount: 0,
        failureCount: 2,
        results: itemResults,
      );

      expect(result.isFullySuccessful, isFalse);
      expect(result.isPartiallySuccessful, isFalse);
      expect(result.isTotalFailure, isTrue);
    });
  });

  group('ConflictResolution', () {
    test('creates resolution with resolved data', () {
      final resolution = ConflictResolution(
        strategy: ConflictResolutionStrategy.merge,
        resolvedData: {'name': 'Merged Product', 'price': 100},
        preserved: true,
        requiresManualResolution: false,
      );

      expect(resolution.strategy, ConflictResolutionStrategy.merge);
      expect(resolution.resolvedData['name'], 'Merged Product');
      expect(resolution.requiresManualResolution, isFalse);
    });

    test('creates resolution requiring manual review', () {
      final resolution = ConflictResolution(
        strategy: ConflictResolutionStrategy.preserveBoth,
        resolvedData: {},
        preserved: true,
        requiresManualResolution: true,
      );

      expect(resolution.strategy, ConflictResolutionStrategy.preserveBoth);
      expect(resolution.requiresManualResolution, isTrue);
    });
  });
}
