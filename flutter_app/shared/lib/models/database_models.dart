// SQLite models for Flutter (local database)
// Mirrors PostgreSQL schema but simplified for offline use

class Store {
  final int? id;
  final String name;
  final String? location;
  final int? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  Store({
    this.id,
    required this.name,
    this.location,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'location': location,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Store.fromMap(Map<String, dynamic> map) {
    return Store(
      id: map['id'],
      name: map['name'],
      location: map['location'],
      createdBy: map['created_by'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }
}

class User {
  final int? id;
  final String username;
  final String passwordHash;
  final String role; // superadmin, admin, cashier
  final int? storeId;
  final DateTime createdAt;
  final DateTime updatedAt;

  User({
    this.id,
    required this.username,
    required this.passwordHash,
    required this.role,
    this.storeId,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'password_hash': passwordHash,
      'role': role,
      'store_id': storeId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      username: map['username'],
      passwordHash: map['password_hash'],
      role: map['role'],
      storeId: map['store_id'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }
}

class Product {
  final int? id;
  final String name;
  final String? description;
  final double price;
  final int stockQuantity;
  final int storeId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    this.id,
    required this.name,
    this.description,
    required this.price,
    required this.stockQuantity,
    required this.storeId,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'stock_quantity': stockQuantity,
      'store_id': storeId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      price: map['price'],
      stockQuantity: map['stock_quantity'],
      storeId: map['store_id'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }
}

class Sale {
  final int? id;
  final int userId;
  final int storeId;
  final double totalAmount;
  final String? paymentMethod;
  final String? paynowReference;
  final String status;
  final DateTime createdAt;

  Sale({
    this.id,
    required this.userId,
    required this.storeId,
    required this.totalAmount,
    this.paymentMethod,
    this.paynowReference,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'store_id': storeId,
      'total_amount': totalAmount,
      'payment_method': paymentMethod,
      'paynow_reference': paynowReference,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: map['id'],
      userId: map['user_id'],
      storeId: map['store_id'],
      totalAmount: map['total_amount'],
      paymentMethod: map['payment_method'],
      paynowReference: map['paynow_reference'],
      status: map['status'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}

class SaleItem {
  final int? id;
  final int saleId;
  final int productId;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  SaleItem({
    this.id,
    required this.saleId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sale_id': saleId,
      'product_id': productId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
    };
  }

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      id: map['id'],
      saleId: map['sale_id'],
      productId: map['product_id'],
      quantity: map['quantity'],
      unitPrice: map['unit_price'],
      totalPrice: map['total_price'],
    );
  }
}

class InventoryLog {
  final int? id;
  final int productId;
  final int quantityChange;
  final String reason;
  final int userId;
  final DateTime createdAt;

  InventoryLog({
    this.id,
    required this.productId,
    required this.quantityChange,
    required this.reason,
    required this.userId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'quantity_change': quantityChange,
      'reason': reason,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory InventoryLog.fromMap(Map<String, dynamic> map) {
    return InventoryLog(
      id: map['id'],
      productId: map['product_id'],
      quantityChange: map['quantity_change'],
      reason: map['reason'],
      userId: map['user_id'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
