import 'package:flutter/material.dart';
import 'package:mobile/theme/tokens.dart';

class BadgeWidget extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  const BadgeWidget(
      {super.key,
      required this.label,
      this.backgroundColor = AppColors.secondaryAccent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
