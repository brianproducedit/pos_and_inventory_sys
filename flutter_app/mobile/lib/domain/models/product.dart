class Product {
  final int? id;
  final int? serverId;
  final int? storeId;
  final String name;
  final String sku;
  final double price;
  final int stockQuantity;
  final bool isSynced;
  final int? lastUpdated;

  Product({
    this.id,
    this.serverId,
    this.storeId,
    required this.name,
    required this.sku,
    required this.price,
    required this.stockQuantity,
    this.isSynced = false,
    this.lastUpdated,
  });

  factory Product.fromMap(Map<String, dynamic> m) {
    return Product(
      id: m['id'] as int?,
      serverId: m['server_id'] as int?,
      storeId: m['store_id'] as int?,
      name: m['name'] as String? ?? '',
      sku: m['sku'] as String? ?? '',
      price: (m['price'] as num?)?.toDouble() ?? 0.0,
      stockQuantity: m['stock_quantity'] as int? ?? 0,
      isSynced: (m['is_synced'] as int? ?? 0) == 1,
      lastUpdated: m['last_updated'] as int?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'server_id': serverId,
        'store_id': storeId,
        'name': name,
        'sku': sku,
        'price': price,
        'stock_quantity': stockQuantity,
        'is_synced': isSynced ? 1 : 0,
        'last_updated': lastUpdated,
      };

  Map<String, dynamic> toJson() => toMap();

  factory Product.fromJson(Map<String, dynamic> json) => Product.fromMap(json);

  operator [](String other) {}
}
