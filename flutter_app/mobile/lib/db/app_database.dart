import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_sqflite/drift_sqflite.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
// import 'package:uuid/uuid.dart';

part 'app_database.g.dart';

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  RealColumn get price => real().withDefault(const Constant(0.0))();
  IntColumn get stockQuantity => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get storeId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientTempId => text().nullable()();
  TextColumn get resourceType => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
}

@DriftDatabase(tables: [Products, SyncQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // Test-friendly constructor that accepts a QueryExecutor directly.
  AppDatabase._(QueryExecutor executor) : super(executor);

  /// Create a database instance backed by a file at [path]. Useful for tests
  /// that need a temporary on-disk DB.
  static Future<AppDatabase> openWithPath(String path) async {
    final exec = SqfliteQueryExecutor(path: path, logStatements: false);
    return AppDatabase._(exec);
  }

  /// Create an in-memory AppDatabase suitable for fast, deterministic tests.
  static AppDatabase inMemory() {
    return AppDatabase._(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 1;

  // Products DAO
  Future<int> insertProduct(ProductsCompanion entry) =>
      into(products).insert(entry);
  Future<List<Product>> getAllProducts() => select(products).get();
  Future<Product?> getProductByClientId(String clientId) =>
      (select(products)..where((p) => p.clientId.equals(clientId)))
          .getSingleOrNull();
  Future<int> updateProductServerId(String clientId, int serverId) async {
    final p = await getProductByClientId(clientId);
    if (p == null) return 0;
    return (update(products)..where((tbl) => tbl.clientId.equals(clientId)))
        .write(
      ProductsCompanion(
        clientId: Value(null),
      ),
    );
  }

  // Sync queue DAO
  Future<int> enqueueChange(
      {String? clientTempId,
      required String resourceType,
      required String operation,
      required String payloadJson}) {
    return into(syncQueue).insert(SyncQueueCompanion.insert(
      clientTempId:
          clientTempId == null ? const Value.absent() : Value(clientTempId),
      resourceType: resourceType,
      operation: operation,
      payloadJson: payloadJson,
    ));
  }

  Future<List<SyncQueueData>> getPendingChanges() => select(syncQueue).get();
  Future<int> deleteQueueItem(int id) =>
      (delete(syncQueue)..where((t) => t.id.equals(id))).go();

  /// Update raw payload JSON for a queue item. Useful for attaching metadata
  /// (e.g., assigning a store_id to product create payloads).
  Future<int> updateQueuePayload(int id, String payloadJson) =>
      (update(syncQueue)..where((t) => t.id.equals(id))).write(
        SyncQueueCompanion(
          payloadJson: Value(payloadJson),
        ),
      );

  /// Async constructor helper usable from background isolates.
  static Future<AppDatabase> open() async {
    // The constructor uses a LazyDatabase which resolves the actual file path
    // lazily, so constructing the DB instance is safe here.
    return AppDatabase();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app.sqlite'));
    // `SqfliteQueryExecutor` expects the named parameter `path` (not `databasePath`)
    return SqfliteQueryExecutor(path: file.path, logStatements: false);
  });
}
