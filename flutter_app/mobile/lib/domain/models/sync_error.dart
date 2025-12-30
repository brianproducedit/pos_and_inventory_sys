class SyncError {
  final int? id;
  final int queueId;
  final String tableName;
  final int rowId;
  final String error;
  final int createdAt;

  SyncError({
    this.id,
    required this.queueId,
    required this.tableName,
    required this.rowId,
    required this.error,
    required this.createdAt,
  });

  factory SyncError.fromMap(Map<String, dynamic> m) => SyncError(
        id: m['id'] as int?,
        queueId: m['queue_id'] as int,
        tableName: m['table_name'] as String,
        rowId: m['row_id'] as int,
        error: m['error'] as String,
        createdAt: m['created_at'] as int,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'queue_id': queueId,
        'table_name': tableName,
        'row_id': rowId,
        'error': error,
        'created_at': createdAt,
      };
}
