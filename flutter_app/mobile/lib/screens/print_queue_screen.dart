import 'package:flutter/material.dart';
import '../services/bluetooth_printer_service.dart';
import 'package:intl/intl.dart';

/// Screen for managing print queue
class PrintQueueScreen extends StatefulWidget {
  final BluetoothPrinterService printerService;

  const PrintQueueScreen({
    Key? key,
    required this.printerService,
  }) : super(key: key);

  @override
  State<PrintQueueScreen> createState() => _PrintQueueScreenState();
}

class _PrintQueueScreenState extends State<PrintQueueScreen> {
  @override
  void initState() {
    super.initState();
    widget.printerService.addListener(_onPrinterServiceChanged);
  }

  @override
  void dispose() {
    widget.printerService.removeListener(_onPrinterServiceChanged);
    super.dispose();
  }

  void _onPrinterServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = widget.printerService.printQueue;
    final pendingJobs = queue.where((j) => j.isPending).toList();
    final failedJobs = queue.where((j) => j.isFailed).toList();
    final completedJobs = queue.where((j) => j.isComplete).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Print Queue (${queue.length})'),
        actions: [
          if (completedJobs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear Completed',
              onPressed: () {
                widget.printerService.clearCompletedJobs();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cleared completed jobs'),
                  ),
                );
              },
            ),
        ],
      ),
      body: queue.isEmpty
          ? _buildEmptyState()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Connection status
                _buildConnectionBanner(),
                
                const SizedBox(height: 16),

                // Pending jobs
                if (pendingJobs.isNotEmpty) ...[
                  _buildSectionHeader('Pending', pendingJobs.length, Colors.blue),
                  ...pendingJobs.map((job) => _buildJobCard(job)),
                  const SizedBox(height: 16),
                ],

                // Failed jobs
                if (failedJobs.isNotEmpty) ...[
                  _buildSectionHeader('Failed', failedJobs.length, Colors.red),
                  ...failedJobs.map((job) => _buildJobCard(job)),
                  const SizedBox(height: 16),
                ],

                // Completed jobs
                if (completedJobs.isNotEmpty) ...[
                  _buildSectionHeader('Completed', completedJobs.length, Colors.green),
                  ...completedJobs.map((job) => _buildJobCard(job)),
                ],
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.print_disabled,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Print Jobs',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Receipts will appear here when queued',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionBanner() {
    final isConnected = widget.printerService.isConnected;
    final connectedPrinter = widget.printerService.connectedPrinter;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green[50] : Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.print : Icons.print_disabled,
            color: isConnected ? Colors.green[700] : Colors.orange[700],
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? 'Printer Connected' : 'Printer Disconnected',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isConnected ? Colors.green[700] : Colors.orange[700],
                  ),
                ),
                if (isConnected && connectedPrinter != null)
                  Text(
                    connectedPrinter.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green[700],
                    ),
                  )
                else
                  Text(
                    'Jobs will print when printer connects',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[700],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$title ($count)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard(PrintJob job) {
    final dateFormat = DateFormat('MMM d, h:mm a');
    
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (job.status) {
      case PrintJobStatus.queued:
        statusColor = Colors.blue;
        statusIcon = Icons.schedule;
        statusText = 'Queued';
        break;
      case PrintJobStatus.printing:
        statusColor = Colors.orange;
        statusIcon = Icons.print;
        statusText = 'Printing...';
        break;
      case PrintJobStatus.completed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Printed';
        break;
      case PrintJobStatus.failed:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        statusText = 'Failed';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  statusText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                const Spacer(),
                if (job.status == PrintJobStatus.failed)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Retry',
                    color: Colors.blue,
                    onPressed: () {
                      widget.printerService.retryJob(job.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Job queued for retry')),
                      );
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  tooltip: 'Remove',
                  color: Colors.grey,
                  onPressed: () {
                    widget.printerService.removeJob(job.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Job removed')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            
            // Receipt details
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Receipt #${job.receipt.transactionNumber}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${job.receipt.items.length} item(s) • \$${job.receipt.total.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Timestamps
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Queued: ${dateFormat.format(job.queuedAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            
            if (job.printedAt != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.check, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Printed: ${dateFormat.format(job.printedAt!)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
            
            // Error message
            if (job.errorMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, size: 16, color: Colors.red[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        job.errorMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // Retry count
            if (job.retryCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Retry attempts: ${job.retryCount}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
