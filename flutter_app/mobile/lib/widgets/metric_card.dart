import 'package:flutter/material.dart';

enum TrendDirection { up, down, flat }

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final double? trendPercent;
  final TrendDirection trendDirection;
  final Widget? footer;

  const MetricCard(
      {super.key,
      required this.title,
      required this.value,
      required this.icon,
      required this.color,
      this.subtitle,
      this.trendPercent,
      this.trendDirection = TrendDirection.flat,
      this.footer});

  @override
  Widget build(BuildContext context) {
    Widget buildTrend() {
      if (trendPercent == null) return const SizedBox.shrink();
      final isUp = trendDirection == TrendDirection.up;
      final trendColor = isUp
          ? Colors.green
          : (trendDirection == TrendDirection.down ? Colors.red : Colors.grey);
      final iconData = isUp
          ? Icons.arrow_upward
          : (trendDirection == TrendDirection.down
              ? Icons.arrow_downward
              : Icons.remove);

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 14, color: trendColor),
          const SizedBox(width: 4),
          Text('${trendPercent!.toStringAsFixed(0)}%',
              style: TextStyle(
                  fontSize: 12,
                  color: trendColor,
                  fontWeight: FontWeight.w600)),
        ],
      );
    }

    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 8),
            Text(value,
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: color, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onBackground.withOpacity(0.7)),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 8),
            buildTrend(),
            if (footer != null) ...[
              const SizedBox(height: 12),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}
