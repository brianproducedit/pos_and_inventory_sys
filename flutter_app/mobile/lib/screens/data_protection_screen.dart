import 'package:flutter/material.dart';
import 'package:mobile/widgets/primary_dialog.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/data_protection_provider.dart';
import '../services/data_protection_service.dart';

/// Screen for managing data protection settings and backups.
///
/// Features:
/// - View list of available backups
/// - Create manual backup
/// - Restore from backup
/// - Run integrity check
/// - Export for uninstall protection
class DataProtectionScreen extends StatefulWidget {
  const DataProtectionScreen({super.key});

  @override
  State<DataProtectionScreen> createState() => _DataProtectionScreenState();
}

class _DataProtectionScreenState extends State<DataProtectionScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Refresh backup list on screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataProtectionProvider>().refreshBackupList();
    });
  }

  Future<void> _createBackup() async {
    setState(() => _isLoading = true);

    try {
      final provider = context.read<DataProtectionProvider>();
      final result = await provider.createBackup(reason: 'manual');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.success
                ? '✅ Backup created successfully'
                : '❌ Backup failed: ${result.error}'),
            backgroundColor: result.success ? Colors.green : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreFromBackup(BackupMetadata backup) async {
    // Confirm restore
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Restore from Backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to restore from this backup?'),
            const SizedBox(height: 16),
            Text('Backup: ${backup.filename}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
                'Created: ${DateFormat.yMd().add_jm().format(backup.timestamp)}'),
            Text('Reason: ${backup.reason}'),
            const SizedBox(height: 16),
            const Text(
              '⚠️ Current data will be backed up before restore.',
              style: TextStyle(color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final provider = context.read<DataProtectionProvider>();
      final result = await provider.restoreFromBackup(backup);

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Restore completed. Please restart the app.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Restore failed: ${result.error}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runIntegrityCheck() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final provider = context.read<DataProtectionProvider>();
      final report = await provider.runIntegrityCheck();

      if (!mounted) return;
      setState(() => _isLoading = false);
      _showIntegrityReportDialog(report);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showIntegrityReportDialog(IntegrityReport report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: PrimaryDialogTitle(
          title: 'Integrity Report',
          trailing: Icon(
            report.hasIssues ? Icons.warning : Icons.check_circle,
            color: report.hasCriticalIssues
                ? Colors.red
                : (report.hasIssues ? Colors.orange : Colors.green),
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Checked at: ${DateFormat.yMd().add_jm().format(report.checkedAt)}'),
              Text('Tables checked: ${report.tablesChecked.length}'),
              const SizedBox(height: 16),
              if (report.issues.isEmpty)
                const Text(
                  '✅ No issues found. Your data is healthy!',
                  style: TextStyle(color: Colors.green),
                )
              else ...[
                Text(
                  '${report.issues.length} issue(s) found:',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...report.issues.map((issue) => Card(
                      color: _getIssueSeverityColor(issue.severity),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _getIssueSeverityIcon(issue.severity),
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  issue.table,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              issue.description,
                              style: const TextStyle(color: Colors.white),
                            ),
                            if (issue.affectedCount != null)
                              Text(
                                'Affected: ${issue.affectedCount} records',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Color _getIssueSeverityColor(IssueSeverity severity) {
    switch (severity) {
      case IssueSeverity.info:
        return Colors.blue;
      case IssueSeverity.warning:
        return Colors.orange;
      case IssueSeverity.error:
        return Colors.deepOrange;
      case IssueSeverity.critical:
        return Colors.red;
    }
  }

  IconData _getIssueSeverityIcon(IssueSeverity severity) {
    switch (severity) {
      case IssueSeverity.info:
        return Icons.info;
      case IssueSeverity.warning:
        return Icons.warning;
      case IssueSeverity.error:
        return Icons.error;
      case IssueSeverity.critical:
        return Icons.dangerous;
    }
  }

  Future<void> _exportForUninstallProtection() async {
    setState(() => _isLoading = true);

    try {
      final provider = context.read<DataProtectionProvider>();
      final result = await provider.exportForUninstallProtection();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.success
                ? '✅ Data exported for uninstall protection'
                : '❌ Export failed: ${result.error}'),
            backgroundColor: result.success ? Colors.green : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DataProtectionProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Protection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : () => provider.refreshBackupList(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick Actions Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Quick Actions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _createBackup,
                                icon: const Icon(Icons.backup),
                                label: const Text('Create Backup'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _runIntegrityCheck,
                                icon: const Icon(Icons.health_and_safety),
                                label: const Text('Check Integrity'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _exportForUninstallProtection,
                                icon: const Icon(Icons.upload),
                                label: const Text('Export Data'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Status Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Protection Status',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _StatusRow(
                            icon: Icons.shield,
                            label: 'Service Status',
                            value:
                                provider.isInitialized ? 'Active' : 'Inactive',
                            isGood: provider.isInitialized,
                          ),
                          _StatusRow(
                            icon: Icons.backup,
                            label: 'Available Backups',
                            value: '${provider.backups.length}',
                            isGood: provider.backups.isNotEmpty,
                          ),
                          if (provider.lastIntegrityReport != null) ...[
                            _StatusRow(
                              icon: Icons.health_and_safety,
                              label: 'Last Integrity Check',
                              value: provider.lastIntegrityReport!.hasIssues
                                  ? '${provider.lastIntegrityReport!.issues.length} issues'
                                  : 'Healthy',
                              isGood: !provider.lastIntegrityReport!.hasIssues,
                            ),
                          ],
                          if (provider.lastError != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error,
                                      color: Colors.red, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      provider.lastError!,
                                      style: const TextStyle(
                                          color: Colors.red, fontSize: 12),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    onPressed: () => provider.clearError(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Backups List
                  const Text(
                    'Available Backups',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (provider.backups.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            'No backups available.\nCreate your first backup to protect your data.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  else
                    ...provider.backups.map((backup) => Card(
                          child: ListTile(
                            leading:
                                const Icon(Icons.backup, color: Colors.blue),
                            title: Text(
                              DateFormat.yMd()
                                  .add_jm()
                                  .format(backup.timestamp),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Reason: ${backup.reason}'),
                                Text(
                                  'Size: ${(backup.sizeBytes / 1024).toStringAsFixed(1)} KB',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.restore),
                              onPressed: () => _restoreFromBackup(backup),
                              tooltip: 'Restore',
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isGood;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isGood,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: isGood ? Colors.green : Colors.orange),
          const SizedBox(width: 8),
          Text(label),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isGood ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
}
