import 'package:flutter/material.dart';
import 'package:mobile/services/time_service.dart';
import 'package:mobile/theme/tokens.dart';

class ReceiptCard extends StatelessWidget {
  final Map<String, dynamic> receipt;
  final VoidCallback? onPrint;
  final VoidCallback? onExport;

  const ReceiptCard(
      {super.key, required this.receipt, this.onPrint, this.onExport});

  @override
  Widget build(BuildContext context) {
    final total = (receipt['total'] is num)
        ? (receipt['total'] as num).toStringAsFixed(2)
        : (receipt['total']?.toString() ?? '0.00');

    final dateRaw = receipt['created_at'];
    String dateStr = '';
    try {
      if (dateRaw == null) {
        dateStr = '';
      } else if (dateRaw is DateTime) {
        dateStr = TimeService.instance.formatDateTime(dateRaw);
      } else if (dateRaw is String) {
        dateStr = TimeService.instance.formatDateTime(DateTime.parse(dateRaw));
      } else {
        dateStr = dateRaw.toString();
      }
    } catch (e) {
      dateStr = dateRaw?.toString() ?? '';
    }

    final items = receipt['items_count']?.toString() ?? '0';

    return Card(
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListTile(
        title: Text(
          receipt['reference'] ?? 'Receipt #${receipt['id']}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          'Items: $items • Total: \$$total\n$dateStr',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.print),
              color: AppColors.primaryBrand,
              tooltip: 'Print',
              onPressed: () async {
                if (onPrint != null) {
                  onPrint!();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.share),
              color: AppColors.secondaryAccent,
              tooltip: 'Export',
              onPressed: () async {
                if (onExport != null) {
                  onExport!();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
