enum UserRole { superadmin, admin, cashier }

class User {
  final int? id;
  final int? serverId;
  final String username;
  final String? fullName;
  final UserRole role;
  final bool isActive;
  final int? storeId;
  final int? createdAt;
  final int? updatedAt;

  User({
    this.id,
    this.serverId,
    required this.username,
    this.fullName,
    required this.role,
    this.isActive = true,
    this.storeId,
    this.createdAt,
    this.updatedAt,
  });

  factory User.fromMap(Map<String, dynamic> m) {
    UserRole parseRole(String? r) {
      switch (r) {
        case 'admin':
          return UserRole.admin;
        case 'cashier':
          return UserRole.cashier;
        case 'superadmin':
        default:
          return UserRole.superadmin;
      }
    }

    return User(
      id: m['id'] as int?,
      serverId: m['server_id'] as int?,
      username: m['username'] as String? ?? '',
      fullName: m['full_name'] as String?,
      role: parseRole(m['role'] as String?),
      isActive: (m['is_active'] as int? ?? 1) == 1,
      storeId: m['store_id'] as int?,
      createdAt: (m['created_at'] as int?),
      updatedAt: (m['updated_at'] as int?),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'server_id': serverId,
        'username': username,
        'full_name': fullName,
        'role': role.name,
        'is_active': isActive ? 1 : 0,
        'store_id': storeId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  Map<String, dynamic> toJson() => toMap();

  factory User.fromJson(Map<String, dynamic> json) => User.fromMap(json);
}
