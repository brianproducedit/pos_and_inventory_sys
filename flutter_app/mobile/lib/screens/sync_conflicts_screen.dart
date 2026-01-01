import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import '../models/sync_conflict.dart' as conflict_model;
import '../services/sync_worker.dart';
import '../db/app_database.dart';

/// Screen for viewing and resolving sync conflicts
class SyncConflictsScreen extends StatefulWidget {
  final conflict_model.ConflictManager conflictManager;
  final SyncWorker syncWorker;

  const SyncConflictsScreen({
    Key? key,
    required this.conflictManager,
    required this.syncWorker,
  }) : super(key: key);

  @override
  State<SyncConflictsScreen> createState() => _SyncConflictsScreenState();
}

class _SyncConflictsScreenState extends State<SyncConflictsScreen> {
  bool _isResolving = false;

  @override
  Widget build(BuildContext context) {
    final conflicts = widget.conflictManager.getPendingConflicts();

    return Scaffold(
      appBar: AppBar(
        title: Text('Sync Conflicts (${conflicts.length})'),
        backgroundColor: Colors.orange,
        actions: [
          if (conflicts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Help',
              onPressed: _showHelpDialog,
            ),
        ],
      ),
      body: conflicts.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: conflicts.length,
              itemBuilder: (context, index) {
                return _buildConflictCard(conflicts[index]);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 80,
            color: Colors.green[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No Conflicts',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'All data is synchronized',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildConflictCard(conflict_model.SyncConflict conflict) {
    final conflictingFields = conflict.getConflictingFields();
    final isUrgent = DateTime.now().difference(conflict.detectedAt) >
        const Duration(hours: 24);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isUrgent
            ? BorderSide(color: Colors.red.shade300, width: 2)
            : BorderSide.none,
      ),
      child: ExpansionTile(
        leading: Icon(
          _getResourceIcon(conflict.resourceType),
          color: isUrgent ? Colors.red : Colors.orange,
          size: 32,
        ),
        title: Text(
          _getResourceLabel(conflict.resourceType),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(conflict.getDescription()),
            const SizedBox(height: 4),
            Text(
              '${conflictingFields.length} field(s) in conflict',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
            if (isUrgent)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'URGENT: Pending for ${_formatDuration(DateTime.now().difference(conflict.detectedAt))}',
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConflictDetails(conflict, conflictingFields),
                const SizedBox(height: 16),
                _buildResolutionButtons(conflict),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConflictDetails(
      conflict_model.SyncConflict conflict, List<String> conflictingFields) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Conflicting Fields:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        ...conflictingFields.map((field) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatFieldName(field),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    conflict.getFieldSummary(field),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildResolutionButtons(conflict_model.SyncConflict conflict) {
    return Column(
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Choose Resolution:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isResolving
                    ? null
                    : () => _resolveConflict(
                          conflict,
                          conflict_model.ConflictResolution.useLocal,
                        ),
                icon: const Icon(Icons.phone_android),
                label: const Text('Use Local'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isResolving
                    ? null
                    : () => _resolveConflict(
                          conflict,
                          conflict_model.ConflictResolution.useServer,
                        ),
                icon: const Icon(Icons.cloud),
                label: const Text('Use Server'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isResolving
                    ? null
                    : () => _resolveConflict(
                          conflict,
                          conflict_model.ConflictResolution.merge,
                        ),
                icon: const Icon(Icons.merge_type),
                label: const Text('Merge (Manual)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isResolving
                    ? null
                    : () => _resolveConflict(
                          conflict,
                          conflict_model.ConflictResolution.skip,
                        ),
                icon: const Icon(Icons.schedule),
                label: const Text('Skip'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _resolveConflict(
    conflict_model.SyncConflict conflict,
    conflict_model.ConflictResolution resolution,
  ) async {
    if (resolution == conflict_model.ConflictResolution.merge) {
      // Show merge dialog for manual field selection
      await _showMergeDialog(conflict);
      return;
    }

    if (resolution == conflict_model.ConflictResolution.skip) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conflict skipped. Will remain pending.'),
        ),
      );
      return;
    }

    setState(() => _isResolving = true);

    try {
      // Apply the resolution
      final result = conflict_model.ConflictResolutionResult(
        conflict: conflict,
        resolution: resolution,
      );

      await _applyResolution(result);

      // Remove from conflict manager
      widget.conflictManager.removeConflict(conflict);

      if (mounted) {
        setState(() => _isResolving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Conflict resolved using ${resolution == conflict_model.ConflictResolution.useLocal ? "local" : "server"} version',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isResolving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resolve conflict: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _applyResolution(conflict_model.ConflictResolutionResult result) async {
    // This would call the appropriate repository method to apply the resolution
    // For now, just update sync status in database
    final db = widget.syncWorker.db;

    switch (result.conflict.resourceType) {
      case 'user':
        await (db.update(db.users)
              ..where((u) => u.id.equals(result.conflict.localId)))
            .write(UsersCompanion(
          syncStatus: drift.Value(SyncStatus.synced),
        ));
        break;
      case 'product':
        await (db.update(db.products)
              ..where((p) => p.id.equals(result.conflict.localId)))
            .write(ProductsCompanion(
          syncStatus: drift.Value(SyncStatus.synced),
        ));
        break;
      // Add other resource types as needed
    }
  }

  Future<void> _showMergeDialog(conflict_model.SyncConflict conflict) async {
    // Show dialog for manual field selection
    // This would be a complex form allowing user to pick field-by-field
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual Merge'),
        content: const Text(
          'Manual merge functionality will allow you to choose which value to keep for each conflicting field.\n\nThis feature is coming soon!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Conflicts Help'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'What are sync conflicts?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sync conflicts occur when the same data is modified both locally and on the server. You need to choose which version to keep.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Resolution Options:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildHelpItem(
                'Use Local',
                'Keep your local changes and discard server changes',
              ),
              _buildHelpItem(
                'Use Server',
                'Discard your local changes and use server version',
              ),
              _buildHelpItem(
                'Merge (Manual)',
                'Manually choose which fields to keep from each version',
              ),
              _buildHelpItem(
                'Skip',
                'Leave the conflict unresolved for now',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: description),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getResourceIcon(String resourceType) {
    switch (resourceType) {
      case 'user':
        return Icons.person;
      case 'product':
        return Icons.inventory;
      case 'sale':
        return Icons.shopping_cart;
      case 'store':
        return Icons.store;
      default:
        return Icons.error_outline;
    }
  }

  String _getResourceLabel(String resourceType) {
    switch (resourceType) {
      case 'user':
        return 'User Account';
      case 'product':
        return 'Product';
      case 'sale':
        return 'Sale Transaction';
      case 'store':
        return 'Store';
      default:
        return 'Unknown Resource';
    }
  }

  String _formatFieldName(String field) {
    return field
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays} day${duration.inDays > 1 ? "s" : ""}';
    } else if (duration.inHours > 0) {
      return '${duration.inHours} hour${duration.inHours > 1 ? "s" : ""}';
    } else {
      return '${duration.inMinutes} minute${duration.inMinutes > 1 ? "s" : ""}';
    }
  }
}
