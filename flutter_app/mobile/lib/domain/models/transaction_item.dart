class TransactionItem {
  final int? id;
  final int transactionId;
  final int productId;
  final int quantity;
  final double unitPrice;
  final double? totalPrice;

  TransactionItem({
    this.id,
    required this.transactionId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.totalPrice,
  });

  factory TransactionItem.fromMap(Map<String, dynamic> m) => TransactionItem(
        id: m['id'] as int?,
        transactionId: m['transaction_id'] as int,
        productId: m['product_id'] as int,
        quantity: m['quantity'] as int,
        unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0.0,
        totalPrice: (m['total_price'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'transaction_id': transactionId,
        'product_id': productId,
        'quantity': quantity,
        'unit_price': unitPrice,
        'total_price': totalPrice,
      };
}
