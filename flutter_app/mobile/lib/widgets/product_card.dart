import 'package:flutter/material.dart';
import 'package:mobile/widgets/primary_button.dart';

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onAdd;
  const ProductCard({super.key, required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final name = product['name'] ?? 'Unknown Product';
    final price = product['price'] ?? 0.0;
    final stock = product['stock_quantity'] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        child: InkWell(
          onTap: onAdd,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center),
                const SizedBox(height: 2),
                Text('\$${(price as num).toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.green, fontSize: 14)),
                const SizedBox(height: 2),
                Text('Stock: $stock',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 4),
                Transform.translate(
                  offset: const Offset(0, -6),
                  child: SizedBox(
                    height: 32,
                    child: PrimaryButton(
                        onPressed: onAdd, child: const Text('Add')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
