import 'package:flutter/material.dart';
import 'package:mobile/theme/tokens.dart';

class PrimaryDialogTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Color? textColor;

  const PrimaryDialogTitle(
      {super.key, required this.title, this.trailing, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: textColor ?? AppColors.primaryBrand,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
