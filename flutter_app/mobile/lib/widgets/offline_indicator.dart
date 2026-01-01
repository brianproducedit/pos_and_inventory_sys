import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';

/// A widget that displays the current online/offline status and pending sync count.
/// Shows a banner at the top of the screen when offline or when there are pending changes.
class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncProvider>(
      builder: (context, syncProvider, child) {
        if (syncProvider.isOnline && syncProvider.pendingCount == 0) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: syncProvider.isOnline
                ? Colors.orange.shade100
                : Colors.red.shade100,
            border: Border(
              bottom: BorderSide(
                color: syncProvider.isOnline
                    ? Colors.orange.shade300
                    : Colors.red.shade300,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                syncProvider.isOnline ? Icons.sync : Icons.cloud_off,
                size: 18,
                color: syncProvider.isOnline
                    ? Colors.orange.shade700
                    : Colors.red.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  syncProvider.isOnline
                      ? '${syncProvider.pendingCount} changes pending sync'
                      : 'Offline - Changes will sync when connected',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: syncProvider.isOnline
                        ? Colors.orange.shade800
                        : Colors.red.shade800,
                  ),
                ),
              ),
              if (syncProvider.isOnline && !syncProvider.isLoading)
                TextButton(
                  onPressed: () => syncProvider.syncNow(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Sync Now'),
                ),
              if (syncProvider.isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A compact offline indicator for use in app bars
class OfflineStatusIcon extends StatelessWidget {
  const OfflineStatusIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncProvider>(
      builder: (context, syncProvider, child) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: syncProvider.isOnline
              ? (syncProvider.pendingCount > 0
                  ? Badge(
                      label: Text('${syncProvider.pendingCount}'),
                      child: IconButton(
                        key: const ValueKey('sync_pending'),
                        icon: const Icon(Icons.sync),
                        tooltip: '${syncProvider.pendingCount} changes pending',
                        onPressed: syncProvider.isLoading
                            ? null
                            : () => syncProvider.syncNow(),
                      ),
                    )
                  : IconButton(
                      key: const ValueKey('sync_done'),
                      icon: const Icon(Icons.cloud_done, color: Colors.green),
                      tooltip: 'All changes synced',
                      onPressed: null,
                    ))
              : IconButton(
                  key: const ValueKey('offline'),
                  icon: const Icon(Icons.cloud_off, color: Colors.red),
                  tooltip: 'Offline - Changes will sync when connected',
                  onPressed: null,
                ),
        );
      },
    );
  }
}
