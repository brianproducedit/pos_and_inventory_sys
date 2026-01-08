import 'package:flutter/material.dart';
import 'package:mobile/widgets/primary_button.dart';
import 'package:mobile/theme/tokens.dart';

class ProductListItem extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onAdd;
  final Widget? trailingActions;
  const ProductListItem(
      {super.key,
      required this.product,
      required this.onAdd,
      this.trailingActions});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.secondaryAccent,
        foregroundColor: Colors.white,
        child: Text((product['name'] ?? 'P')[0]),
      ),
      title: Text(product['name'] ?? 'Unknown'),
      subtitle: RichText(
        text: TextSpan(
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
          children: [
            const TextSpan(text: 'Price: '),
            TextSpan(
                text: '\$${(product['price'] ?? 0).toStringAsFixed(2)}',
                style: const TextStyle(color: AppColors.primaryAction)),
            TextSpan(text: ' • Stock: ${product['stock_quantity'] ?? 0}'),
          ],
        ),
      ),
      trailing: trailingActions ??
          SizedBox(
              width: 100,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                PrimaryButton(onPressed: onAdd, child: const Text('Add'))
              ])),
    );
  }
}
