class Store {
  final int? id;
  final String name;
  final String? location;
  final bool isActive;
  final int? createdBy;
  final int? createdAt;
  final int? updatedAt;

  Store({
    this.id,
    required this.name,
    this.location,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Store.fromMap(Map<String, dynamic> m) => Store(
        id: m['id'] as int?,
        name: m['name'] as String? ?? '',
        location: m['location'] as String?,
        isActive: (m['is_active'] as int? ?? 1) == 1,
        createdBy: m['created_by'] as int?,
        createdAt: m['created_at'] as int?,
        updatedAt: m['updated_at'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'location': location,
        'is_active': isActive ? 1 : 0,
        'created_by': createdBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}
