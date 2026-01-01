import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_sqflite/drift_sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Sync status used across all syncable tables.
enum SyncStatus { synced, pending, conflict, error }

/// Application roles aligned with the backend.
enum UserRole { superadmin, admin, cashier }

/// Generic enum<->string converter so Drift can persist enum values.
class EnumNameConverter<T extends Enum> extends TypeConverter<T, String> {
  const EnumNameConverter(this.values);

  final List<T> values;

  @override
  T fromSql(String fromDb) {
    return values.firstWhere((v) => v.name == fromDb);
  }

  @override
  String toSql(T value) {
    return value.name;
  }
}

const syncStatusConverter = EnumNameConverter<SyncStatus>(SyncStatus.values);
const userRoleConverter = EnumNameConverter<UserRole>(UserRole.values);

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientId => text().withDefault(const Constant(''))();
  IntColumn get serverId => integer().nullable()();

  TextColumn get username => text()();
  TextColumn get passwordHash => text()();
  TextColumn get fullName => text().nullable()();
  TextColumn get role => text().map(userRoleConverter)();
  IntColumn get storeId => integer().nullable().references(Stores, #id)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get mustChangePassword =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isLocalOnly => boolean().withDefault(const Constant(false))();

  TextColumn get syncStatus => text()
      .map(syncStatusConverter)
      .withDefault(Constant(SyncStatus.pending.name))();
  DateTimeColumn get lastUpdatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>>? get uniqueKeys => [
        {username}, // Unique username constraint
      ];
}

class Stores extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientId => text().withDefault(const Constant(''))();
  IntColumn get serverId => integer().nullable()();

  TextColumn get name => text()();
  TextColumn get location => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get createdBy => integer().nullable()();

  TextColumn get syncStatus => text()
      .map(syncStatusConverter)
      .withDefault(Constant(SyncStatus.pending.name))();
  DateTimeColumn get lastUpdatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientId => text().withDefault(const Constant(''))();
  IntColumn get serverId => integer().nullable()();

  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get sku => text().nullable()();
  RealColumn get price => real().withDefault(const Constant(0.0))();
  IntColumn get stockQuantity => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get storeId => integer().references(Stores, #id)();

  TextColumn get syncStatus => text()
      .map(syncStatusConverter)
      .withDefault(Constant(SyncStatus.pending.name))();
  DateTimeColumn get lastUpdatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>>? get uniqueKeys => [
        {sku}, // Unique SKU constraint (when not null)
      ];
}

class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientId => text().withDefault(const Constant(''))();
  IntColumn get serverId => integer().nullable()();

  TextColumn get transactionNumber => text()();
  IntColumn get userId => integer().references(Users, #id)();
  IntColumn get storeId => integer().references(Stores, #id)();
  RealColumn get totalAmount => real()();
  TextColumn get paymentMethod => text()();
  TextColumn get paymentReference => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('completed'))();

  TextColumn get syncStatus => text()
      .map(syncStatusConverter)
      .withDefault(Constant(SyncStatus.pending.name))();
  DateTimeColumn get lastUpdatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientId => text().withDefault(const Constant(''))();
  IntColumn get serverId => integer().nullable()();

  IntColumn get saleId => integer().references(Sales, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get quantity => integer()();
  RealColumn get unitPrice => real()();
  RealColumn get totalPrice => real()();

  TextColumn get syncStatus => text()
      .map(syncStatusConverter)
      .withDefault(Constant(SyncStatus.pending.name))();
}

class InventoryLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientId => text().withDefault(const Constant(''))();
  IntColumn get serverId => integer().nullable()();

  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get userId => integer().references(Users, #id)();
  IntColumn get quantityChange => integer()();
  TextColumn get reason => text()();

  TextColumn get syncStatus => text()
      .map(syncStatusConverter)
      .withDefault(Constant(SyncStatus.pending.name))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientTempId => text().nullable()();
  TextColumn get resourceType => text()();
  TextColumn get operation => text()();
  TextColumn get entityId => text().nullable()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get errorMessage => text().nullable()();
}

class SyncConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get resourceType => text()();
  TextColumn get resourceId => text()();
  TextColumn get localDataJson => text()();
  TextColumn get serverDataJson => text()();
  TextColumn get resolution => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
}

class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Users,
    Stores,
    Products,
    Sales,
    SaleItems,
    InventoryLogs,
    SyncQueue,
    SyncConflicts,
    SyncMeta,
  ],
)
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Create indexes for performance
          await _createPerformanceIndexes(m);
        },
        onUpgrade: (m, from, to) async {
          if (from == 1 && to == 2) {
            // Migrate from V1 to V2 schema (add sync metadata columns)
            // 1. Create new tables
            await m.createTable(users);
            await m.createTable(stores);
            await m.createTable(sales);
            await m.createTable(saleItems);
            await m.createTable(inventoryLogs);
            await m.createTable(syncConflicts);
            await m.createTable(syncMeta);

            // 2. Migrate Products table: rename old table, create new one, copy data
            await m.issueCustomQuery(
                'ALTER TABLE products RENAME TO products_old');
            await m.createTable(products);

            // Copy existing product data with default sync metadata
            await m.issueCustomQuery('''
              INSERT INTO products (id, client_id, server_id, name, description, sku, 
                price, stock_quantity, is_active, store_id, sync_status, 
                last_updated_at, created_at)
              SELECT id, COALESCE(client_id, ''), id, name, description, NULL,
                price, stock_quantity, is_active, store_id, 'synced',
                COALESCE(updated_at, created_at, datetime('now')), 
                COALESCE(created_at, datetime('now'))
              FROM products_old
            ''');

            await m.issueCustomQuery('DROP TABLE products_old');

            // 3. Migrate SyncQueue table
            await m.issueCustomQuery(
                'ALTER TABLE sync_queue RENAME TO sync_queue_old');
            await m.createTable(syncQueue);

            // Copy sync queue data with new columns
            await m.issueCustomQuery('''
              INSERT INTO sync_queue (id, client_temp_id, resource_type, operation,
                entity_id, payload_json, created_at, last_attempt_at, retry_count, 
                status, error_message)
              SELECT id, client_temp_id, resource_type, operation, NULL,
                payload_json, datetime('now'), last_attempt_at, retry_count,
                'pending', NULL
              FROM sync_queue_old
            ''');

            await m.issueCustomQuery('DROP TABLE sync_queue_old');
          }
        },
      );

  // Products DAO (legacy-friendly methods retained while V2 repositories land)
  Future<int> insertProduct(ProductsCompanion entry) =>
      into(products).insert(entry);

  Future<List<Product>> getAllProducts() => select(products).get();

  Future<Product?> getProductByClientId(String clientId) =>
      (select(products)..where((p) => p.clientId.equals(clientId)))
          .getSingleOrNull();

  Future<int> updateProductServerId(String clientId, int serverId) {
    return (update(products)..where((tbl) => tbl.clientId.equals(clientId)))
        .write(
      ProductsCompanion(
        serverId: Value(serverId),
        syncStatus: Value(SyncStatus.synced),
        clientId: const Value(''),
      ),
    );
  }

  // Sync queue DAO
  Future<int> enqueueChange({
    String? clientTempId,
    required String resourceType,
    required String operation,
    required String payloadJson,
    String? entityId,
  }) {
    return into(syncQueue).insert(SyncQueueCompanion.insert(
      clientTempId:
          clientTempId == null ? const Value.absent() : Value(clientTempId),
      resourceType: resourceType,
      operation: operation,
      entityId: entityId == null ? const Value.absent() : Value(entityId),
      payloadJson: payloadJson,
    ));
  }

  Future<List<SyncQueueData>> getPendingChanges() =>
      (select(syncQueue)..where((q) => q.status.equals('pending'))).get();

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

  /// Create performance indexes for common query patterns
  Future<void> _createPerformanceIndexes(Migrator m) async {
    // Users table indexes
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_users_username ON users(username)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_users_store_id ON users(store_id)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_users_sync_status ON users(sync_status)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_users_server_id ON users(server_id)');

    // Products table indexes
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_products_store_id ON products(store_id)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_products_sync_status ON products(sync_status)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_products_active_store ON products(is_active, store_id)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_products_stock ON products(stock_quantity)');

    // Sales table indexes
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_sales_transaction_number ON sales(transaction_number)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_sales_user_id ON sales(user_id)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_sales_store_id ON sales(store_id)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at DESC)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_sales_sync_status ON sales(sync_status)');

    // Sale Items table indexes
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items(sale_id)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON sale_items(product_id)');

    // Sync Queue table indexes
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_resource ON sync_queue(resource_type, entity_id)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_created_at ON sync_queue(created_at)');

    // Inventory Logs table indexes
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_inventory_logs_product_id ON inventory_logs(product_id)');
    await m.issueCustomQuery(
        'CREATE INDEX IF NOT EXISTS idx_inventory_logs_created_at ON inventory_logs(created_at DESC)');
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
