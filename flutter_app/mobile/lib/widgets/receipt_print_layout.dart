import 'package:flutter/material.dart';
import 'package:mobile/services/time_service.dart';

class PrinterFriendlyReceipt extends StatelessWidget {
  final Map<String, dynamic> receipt;
  const PrinterFriendlyReceipt({super.key, required this.receipt});

  @override
  Widget build(BuildContext context) {
    final items = receipt['items'] as List<Map<String, dynamic>>? ?? [];
    final total = receipt['total']?.toStringAsFixed(2) ??
        (receipt['total']?.toString() ?? '0.00');
    final date = receipt['created_at'];
    final dateStr = date is DateTime
        ? TimeService.instance.formatDateTime(date)
        : date?.toString() ?? '';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            receipt['reference'] ?? 'Receipt #${receipt['id']}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Date: $dateStr'),
          const Divider(height: 24),
          ...items.map((it) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                    '${it['qty'] ?? 1} x ${it['name']} - ${it['price'] ?? ''}'),
              )),
          const Divider(height: 24),
          Text('Total: \$${total}',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
