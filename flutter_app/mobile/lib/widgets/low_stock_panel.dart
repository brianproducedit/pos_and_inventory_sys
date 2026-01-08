import 'package:flutter/material.dart';
import 'package:mobile/theme/tokens.dart';

class LowStockPanel extends StatelessWidget {
  final int count;
  final int criticalCount;
  final VoidCallback? onView;

  const LowStockPanel(
      {super.key,
      required this.count,
      required this.criticalCount,
      this.onView});

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.check_circle, color: AppColors.primaryAction),
          title: Text('All stocks are sufficient'),
        ),
      );
    }

    return Card(
      color: count > 0 ? AppColors.warning.withValues(alpha: 0.08 * 255) : null,
      child: ListTile(
        leading: const Icon(Icons.warning, color: AppColors.warning),
        title: Text('$count low stock alerts'),
        subtitle: Text('$criticalCount critical'),
        trailing: TextButton(onPressed: onView, child: const Text('View')),
      ),
    );
  }
}
