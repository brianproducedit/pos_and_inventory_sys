class InventoryLog {
  final int? id;
  final int productId;
  final int quantityChange;
  final String reason;
  final int userId;
  final int? createdAt;

  InventoryLog({
    this.id,
    required this.productId,
    required this.quantityChange,
    required this.reason,
    required this.userId,
    this.createdAt,
  });

  factory InventoryLog.fromMap(Map<String, dynamic> m) => InventoryLog(
        id: m['id'] as int?,
        productId: m['product_id'] as int,
        quantityChange: m['quantity_change'] as int,
        reason: m['reason'] as String? ?? '',
        userId: m['user_id'] as int,
        createdAt: m['created_at'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'product_id': productId,
        'quantity_change': quantityChange,
        'reason': reason,
        'user_id': userId,
        'created_at': createdAt,
      };
}
