import '../../domain/models/sync_error.dart';
import '../local/database_helper.dart';

class SyncRepository {
  final DatabaseHelper db;

  SyncRepository({required this.db});

  Future<List<SyncError>> getErrors({int limit = 100}) async {
    final rows = await db.getSyncErrors(limit: limit);
    return rows.map((r) => SyncError.fromMap(r)).toList();
  }

  Future<void> clearError(int id) async => db.clearSyncError(id);

  Future<void> clearErrorsForQueue(int queueId) async =>
      db.clearErrorsForQueue(queueId);

  /// Re-enqueue a failed queue item (reset retry_count + status='pending') and clear errors
  Future<void> reenqueueQueueItem(int queueId) async =>
      db.reenqueueQueueItem(queueId);
}
