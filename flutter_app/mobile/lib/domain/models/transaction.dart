class Transaction {
  final int? id;
  final int? serverId;
  final int userId;
  final int storeId;
  final double totalAmount;
  final String? paymentMethod;
  final String? paynowReference;
  final String status;
  final int? createdAt;

  Transaction({
    this.id,
    this.serverId,
    required this.userId,
    required this.storeId,
    required this.totalAmount,
    this.paymentMethod,
    this.paynowReference,
    this.status = 'completed',
    this.createdAt,
  });

  factory Transaction.fromMap(Map<String, dynamic> m) => Transaction(
        id: m['id'] as int?,
        serverId: m['server_id'] as int?,
        userId: m['user_id'] as int? ?? 0,
        storeId: m['store_id'] as int? ?? 0,
        totalAmount: (m['total_amount'] as num?)?.toDouble() ?? 0.0,
        paymentMethod: m['payment_method'] as String?,
        paynowReference: m['paynow_reference'] as String?,
        status: m['status'] as String? ?? 'completed',
        createdAt: m['created_at'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'server_id': serverId,
        'user_id': userId,
        'store_id': storeId,
        'total_amount': totalAmount,
        'payment_method': paymentMethod,
        'paynow_reference': paynowReference,
        'status': status,
        'created_at': createdAt,
      };
}
