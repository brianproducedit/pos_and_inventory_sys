// Sync logic placeholder
// This will handle syncing between local SQLite and server PostgreSQL

class SyncService {
  // Optional callbacks so platform-specific implementations can be injected
  final Future<void> Function()? onSyncData;
  final Future<void> Function()? onPushLocal;
  final Future<void> Function()? onPullServer;

  SyncService({this.onSyncData, this.onPushLocal, this.onPullServer});

  Future<void> syncData() async {
    if (onSyncData != null) return await onSyncData!();
    // Best-effort no-op fallback for shared package consumers
    print('SyncService.syncData: no delegate provided - no-op');
  }

  Future<void> pushLocalChanges() async {
    if (onPushLocal != null) return await onPushLocal!();
    print('SyncService.pushLocalChanges: no delegate provided - no-op');
  }

  Future<void> pullServerChanges() async {
    if (onPullServer != null) return await onPullServer!();
    print('SyncService.pullServerChanges: no delegate provided - no-op');
  }
}
