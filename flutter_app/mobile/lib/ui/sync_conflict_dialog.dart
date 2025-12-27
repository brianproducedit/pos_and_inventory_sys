import 'package:flutter/material.dart';

class SyncConflictDialog extends StatelessWidget {
  final Map<String, dynamic> serverData;
  final VoidCallback onAcceptServer;
  final VoidCallback onForce;

  const SyncConflictDialog({
    super.key,
    required this.serverData,
    required this.onAcceptServer,
    required this.onForce,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sync Conflict'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Server value (preview):'),
          const SizedBox(height: 8),
          Text(serverData.toString(),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          const Text('Choose how to resolve:'),
        ],
      ),
      actions: [
        TextButton(
            onPressed: onAcceptServer, child: const Text('Accept server')),
        ElevatedButton(
            onPressed: onForce, child: const Text('Force (admin only)')),
      ],
    );
  }
}
