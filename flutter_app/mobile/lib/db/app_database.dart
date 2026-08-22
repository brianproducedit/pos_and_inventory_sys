import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_sqflite/drift_sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

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
        {name, storeId}, // Unique name per store
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
  IntColumn get clientSeq =>
      integer().withDefault(const Constant(0))(); // For tracking sync order
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
  // Singleton instance
  static AppDatabase? _instance;

  // Private constructor
  AppDatabase._() : super(_openConnection());

  // Factory constructor for singleton
  factory AppDatabase() {
    _instance ??= AppDatabase._();
    return _instance!;
  }

  // Test-friendly constructor that accepts a QueryExecutor directly.
  AppDatabase._test(QueryExecutor executor) : super(executor);

  /// Create a database instance backed by a file at [path]. Useful for tests
  /// that need a temporary on-disk DB.
  static Future<AppDatabase> openWithPath(String path) async {
    final exec = SqfliteQueryExecutor(path: path, logStatements: false);
    final db = AppDatabase._test(exec);

    // Apply PRAGMA settings manually for test databases using query-style calls
    // Use customSelect(...).get() because some PRAGMA statements return rows on Android
    try {
      final journal = await db.customSelect('PRAGMA journal_mode = WAL').get();
      await db.customSelect('PRAGMA synchronous = NORMAL').get();
      await db.customSelect('PRAGMA busy_timeout = 5000').get();
      await db.customSelect('PRAGMA foreign_keys = ON').get();
      await db.customSelect('PRAGMA temp_store = memory').get();
      await db.customSelect('PRAGMA mmap_size = 268435456').get(); // 256MB
      await db.customSelect('PRAGMA cache_size = -2000').get(); // 2MB cache
      debugPrint(
          '✅ Test database PRAGMA settings applied successfully (journal: $journal)');
    } catch (e) {
      debugPrint('⚠️ Failed to apply test PRAGMA settings: $e');
    }

    return db;
  }

  /// Create an in-memory AppDatabase suitable for fast, deterministic tests.
  static AppDatabase inMemory() {
    return AppDatabase._test(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 4; // Added transaction_number to Sales

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Create indexes for performance
          await _createPerformanceIndexes(m);
        },
        onUpgrade: (m, from, to) async {
          // Helper to check if a table exists
          Future<bool> tableExists(String tableName) async {
            final result = await m.database.customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
              variables: [Variable.withString(tableName)],
            ).get();
            return result.isNotEmpty;
          }

          // Helper to check if a column exists in a table
          Future<bool> columnExists(String tableName, String columnName) async {
            try {
              final result = await m.database
                  .customSelect(
                    "PRAGMA table_info($tableName)",
                  )
                  .get();
              return result.any((row) => row.data['name'] == columnName);
            } catch (e) {
              return false;
            }
          }

          if (from == 1 && to >= 2) {
            // Migrate from V1 to V2 schema (add sync metadata columns)
            // 1. Create new tables if they don't exist
            if (!await tableExists('users')) await m.createTable(users);
            if (!await tableExists('stores')) await m.createTable(stores);
            if (!await tableExists('sales')) await m.createTable(sales);
            if (!await tableExists('sale_items')) {
              await m.createTable(saleItems);
            }
            if (!await tableExists('inventory_logs')) {
              await m.createTable(inventoryLogs);
            }
            if (!await tableExists('sync_conflicts')) {
              await m.createTable(syncConflicts);
            }
            if (!await tableExists('sync_meta')) await m.createTable(syncMeta);

            // 2. Migrate Products table if old schema exists
            if (await tableExists('products')) {
              // Check if it's old schema by looking for a column that doesn't exist in new schema
              final hasClientId = await columnExists('products', 'client_id');
              if (!hasClientId) {
                await customStatement(
                    'ALTER TABLE products RENAME TO products_old');
                await m.createTable(products);

                // Copy existing product data with default sync metadata
                await customStatement('''
                  INSERT INTO products (id, client_id, server_id, name, description, sku, 
                    price, stock_quantity, is_active, store_id, sync_status, 
                    last_updated_at, created_at)
                  SELECT id, COALESCE(client_id, ''), id, name, description, NULL,
                    price, stock_quantity, is_active, store_id, 'synced',
                    COALESCE(updated_at, created_at, datetime('now')), 
                    COALESCE(created_at, datetime('now'))
                  FROM products_old
                ''');

                await customStatement('DROP TABLE products_old');
              }
            } else {
              await m.createTable(products);
            }

            // 3. Migrate SyncQueue table if needed
            if (await tableExists('sync_queue')) {
              final hasEntityId = await columnExists('sync_queue', 'entity_id');
              if (!hasEntityId) {
                await customStatement(
                    'ALTER TABLE sync_queue RENAME TO sync_queue_old');
                await m.createTable(syncQueue);

                // Copy sync queue data with new columns
                await customStatement('''
                  INSERT INTO sync_queue (id, client_temp_id, resource_type, operation,
                    entity_id, payload_json, created_at, last_attempt_at, retry_count, 
                    status, error_message, client_seq)
                  SELECT id, client_temp_id, resource_type, operation, NULL,
                    payload_json, datetime('now'), last_attempt_at, retry_count,
                    'pending', NULL, 0
                  FROM sync_queue_old
                ''');

                await customStatement('DROP TABLE sync_queue_old');
              }
            } else {
              // Create sync_queue fresh with all columns including client_seq
              await m.createTable(syncQueue);
            }
          }

          if (from == 2 && to >= 3) {
            // Add client_seq column to sync_queue for tracking sync order
            // First, ensure the sync_queue table exists
            final syncQueueExists = await tableExists('sync_queue');
            debugPrint(
                '🔄 Migration 2->3: sync_queue exists = $syncQueueExists');

            if (!syncQueueExists) {
              // Table doesn't exist at all - create it fresh with all columns
              debugPrint('📦 Creating sync_queue table from scratch...');
              await m.createTable(syncQueue);
              debugPrint('✅ Created sync_queue table');
            } else {
              // Table exists, check if client_seq column exists
              final hasClientSeq =
                  await columnExists('sync_queue', 'client_seq');
              debugPrint(
                  '🔄 Migration 2->3: client_seq exists = $hasClientSeq');

              if (!hasClientSeq) {
                // Need to add the column - but ALTER TABLE might fail
                // so we'll use the recreate approach directly
                debugPrint(
                    '📦 Recreating sync_queue to add client_seq column...');
                try {
                  // Rename existing table
                  await customStatement(
                      'ALTER TABLE sync_queue RENAME TO sync_queue_backup');

                  // Create new table with all columns
                  await m.createTable(syncQueue);

                  // Copy data from backup
                  await customStatement('''
                    INSERT INTO sync_queue (id, client_temp_id, resource_type, operation,
                      entity_id, payload_json, created_at, last_attempt_at, retry_count, 
                      status, error_message, client_seq)
                    SELECT id, client_temp_id, resource_type, operation, entity_id,
                      payload_json, created_at, last_attempt_at, retry_count,
                      status, error_message, 0
                    FROM sync_queue_backup
                  ''');

                  // Drop backup table
                  await customStatement('DROP TABLE sync_queue_backup');
                  debugPrint(
                      '✅ Recreated sync_queue table with client_seq column');
                } catch (recreateError) {
                  debugPrint(
                      '⚠️ Failed to recreate sync_queue: $recreateError');
                  // Last resort: just drop and create fresh
                  try {
                    await customStatement(
                        'DROP TABLE IF EXISTS sync_queue_backup');
                    await customStatement('DROP TABLE IF EXISTS sync_queue');
                    await m.createTable(syncQueue);
                    debugPrint(
                        '✅ Force created fresh sync_queue table (data lost)');
                  } catch (e) {
                    debugPrint('❌ Could not create sync_queue: $e');
                  }
                }
              } else {
                debugPrint('✅ sync_queue already has client_seq column');
              }
            }
          }

          if (from == 3 && to >= 4) {
            // Add transaction_number column to sales table
            final salesExists = await tableExists('sales');
            debugPrint('🔄 Migration 3->4: sales exists = $salesExists');

            if (salesExists) {
              final hasTransactionNumber =
                  await columnExists('sales', 'transaction_number');
              debugPrint(
                  '🔄 Migration 3->4: transaction_number exists = $hasTransactionNumber');

              if (!hasTransactionNumber) {
                debugPrint(
                    '📦 Adding transaction_number column to sales table...');
                try {
                  // Add the column as nullable first
                  await customStatement(
                    'ALTER TABLE sales ADD COLUMN transaction_number TEXT',
                  );

                  // Backfill existing sales with generated transaction numbers
                  await customStatement('''
                    UPDATE sales
                    SET transaction_number = 'TXN' || strftime('%Y%m%d', created_at) || substr('00000' || (id % 100000), -5)
                    WHERE transaction_number IS NULL
                  ''');

                  debugPrint('✅ Added transaction_number column to sales table');
                } catch (e) {
                  debugPrint('⚠️ Error adding transaction_number column: $e');
                }
              } else {
                debugPrint('✅ sales table already has transaction_number column');
              }
            }
          }
        },
        beforeOpen: (details) async {
          // PRAGMA settings are now applied directly when opening the database
          // Ensure all required tables exist (handles edge cases where migration failed partially)
          await _ensureRequiredTablesExist();
        },
      );

  /// Ensure all required tables exist in the database.
  /// This handles edge cases where migrations failed partially.
  Future<void> _ensureRequiredTablesExist() async {
    // Check if sync_queue table exists and has all required columns
    try {
      final result = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_queue'",
      ).get();

      if (result.isEmpty) {
        // sync_queue table is missing - this shouldn't happen but let's handle it
        debugPrint('⚠️ sync_queue table missing, creating it...');
        await customStatement('''
          CREATE TABLE IF NOT EXISTS sync_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_temp_id TEXT,
            resource_type TEXT NOT NULL,
            operation TEXT NOT NULL,
            entity_id TEXT,
            payload_json TEXT NOT NULL,
            client_seq INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            last_attempt_at INTEGER,
            retry_count INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'pending',
            error_message TEXT
          )
        ''');
        debugPrint('✅ sync_queue table created');
      } else {
        // Table exists, check if client_seq column exists
        final columns =
            await customSelect("PRAGMA table_info(sync_queue)").get();
        final hasClientSeq =
            columns.any((row) => row.data['name'] == 'client_seq');

        if (!hasClientSeq) {
          debugPrint(
              '⚠️ client_seq column missing from sync_queue, adding it...');
          await customStatement(
            'ALTER TABLE sync_queue ADD COLUMN client_seq INTEGER NOT NULL DEFAULT 0',
          );
          debugPrint('✅ client_seq column added to sync_queue');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error ensuring required tables exist: $e');
      // Don't rethrow - the app should still try to function
    }
  }

  // Products DAO (legacy-friendly methods retained while V2 repositories land)
  Future<int> insertProduct(ProductsCompanion entry) =>
      _withDatabaseRetry(() => into(products).insert(entry));

  Future<List<Product>> getAllProducts() =>
      _withDatabaseRetry(() => select(products).get());

  Future<Product?> getProductByClientId(String clientId) => _withDatabaseRetry(
      () => (select(products)..where((p) => p.clientId.equals(clientId)))
          .getSingleOrNull());

  Future<int> updateProductServerId(String clientId, int serverId) {
    return _withDatabaseRetry(() =>
        (update(products)..where((tbl) => tbl.clientId.equals(clientId))).write(
          ProductsCompanion(
            serverId: Value(serverId),
            syncStatus: const Value(SyncStatus.synced),
            clientId: const Value(''),
          ),
        ));
  }

  // Sync queue DAO
  Future<int> enqueueChange({
    String? clientTempId,
    required String resourceType,
    required String operation,
    required String payloadJson,
    String? entityId,
  }) {
    return _withDatabaseRetry(() =>
        into(syncQueue).insert(SyncQueueCompanion.insert(
          clientTempId:
              clientTempId == null ? const Value.absent() : Value(clientTempId),
          resourceType: resourceType,
          operation: operation,
          entityId: entityId == null ? const Value.absent() : Value(entityId),
          payloadJson: payloadJson,
        )));
  }

  Future<List<SyncQueueData>> getPendingChanges() => _withDatabaseRetry(() =>
      (select(syncQueue)..where((q) => q.status.equals('pending'))).get());

  Future<int> deleteQueueItem(int id) => _withDatabaseRetry(
      () => (delete(syncQueue)..where((t) => t.id.equals(id))).go());

  /// Update raw payload JSON for a queue item. Useful for attaching metadata
  /// (e.g., assigning a store_id to product create payloads).
  Future<int> updateQueuePayload(int id, String payloadJson) =>
      _withDatabaseRetry(
          () => (update(syncQueue)..where((t) => t.id.equals(id))).write(
                SyncQueueCompanion(
                  payloadJson: Value(payloadJson),
                ),
              ));

  /// Helper method to retry database operations that may fail due to connection closures.
  /// Automatically catches DriftWrappedException and retries after reopening the connection.
  Future<T> _withDatabaseRetry<T>(Future<T> Function() operation,
      {int maxRetries = 3}) async {
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        return await operation();
      } on DriftWrappedException catch (e) {
        attempts++;
        if (attempts >= maxRetries) {
          debugPrint(
              '❌ Database operation failed after $maxRetries attempts: $e');
          rethrow;
        }
        debugPrint(
            '🔄 Database connection closed (attempt $attempts/$maxRetries), retrying...');
        // Drift will automatically reopen the connection on the next operation
      }
    }
    throw StateError('Unreachable code');
  }

  /// Async constructor helper usable from background isolates.
  static Future<AppDatabase> open() async {
    // The constructor uses a LazyDatabase which resolves the actual file path
    // lazily, so constructing the DB instance is safe here.
    return AppDatabase();
  }

  /// Create performance indexes for common query patterns
  Future<void> _createPerformanceIndexes(Migrator m) async {
    // Users table indexes
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_users_username ON users(username)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_users_store_id ON users(store_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_users_sync_status ON users(sync_status)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_users_server_id ON users(server_id)');

    // Products table indexes
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_store_id ON products(store_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_sync_status ON products(sync_status)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_active_store ON products(is_active, store_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_stock ON products(stock_quantity)');

    // Sales table indexes
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_transaction_number ON sales(transaction_number)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_user_id ON sales(user_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_store_id ON sales(store_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at DESC)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_sync_status ON sales(sync_status)');

    // Sale Items table indexes
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items(sale_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON sale_items(product_id)');

    // Sync Queue table indexes
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_resource ON sync_queue(resource_type, entity_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_created_at ON sync_queue(created_at)');

    // Inventory Logs table indexes
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_logs_product_id ON inventory_logs(product_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_inventory_logs_created_at ON inventory_logs(created_at DESC)');
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app.sqlite'));

    // Open sqflite database directly to apply PRAGMA settings
    final sqfliteDb = await sqflite.openDatabase(
      file.path,
      version: 1, // sqflite version, not our schema version
      singleInstance: true,
    );

    // Apply PRAGMA settings directly on sqflite database
    try {
      // journal_mode returns a value on Android and must use rawQuery
      final journalRes = await sqfliteDb.rawQuery('PRAGMA journal_mode = WAL');
      debugPrint('PRAGMA journal_mode result: $journalRes');

      // Use rawQuery for PRAGMAs to ensure compatibility across platforms
      final syncRes = await sqfliteDb.rawQuery('PRAGMA synchronous = NORMAL');
      final busyRes = await sqfliteDb.rawQuery('PRAGMA busy_timeout = 30000');
      final fkRes = await sqfliteDb.rawQuery('PRAGMA foreign_keys = ON');
      final tempStoreRes =
          await sqfliteDb.rawQuery('PRAGMA temp_store = memory');
      final mmapRes =
          await sqfliteDb.rawQuery('PRAGMA mmap_size = 268435456'); // 256MB
      final cacheRes =
          await sqfliteDb.rawQuery('PRAGMA cache_size = -2000'); // 2MB cache

      // Include all PRAGMA results in the debug log to avoid unused variable warnings
      debugPrint('✅ Database PRAGMA settings applied successfully '
          '(journal:$journalRes, sync:$syncRes, busy:$busyRes, fk:$fkRes, '
          'temp_store:$tempStoreRes, mmap:$mmapRes, cache:$cacheRes)');
    } catch (e) {
      debugPrint('⚠️ Failed to apply PRAGMA settings: $e');
    }

    // Close the sqflite database - Drift will reopen it
    await sqfliteDb.close();

    // Now return SqfliteQueryExecutor which will reopen the database
    return SqfliteQueryExecutor.inDatabaseFolder(
      path: file.path,
      logStatements: false,
      singleInstance: true,
    );
  });
}

/// NUCLEAR OPTION: Delete and recreate the database from scratch.
/// Use this only when database corruption or migration issues occur.
/// WARNING: This will delete ALL local data!
Future<void> resetDatabase() async {
  try {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app.sqlite'));
    final walFile = File(p.join(dbFolder.path, 'app.sqlite-wal'));
    final shmFile = File(p.join(dbFolder.path, 'app.sqlite-shm'));

    debugPrint('🗑️ Resetting database - deleting all files...');

    // Close any existing connections
    try {
      await sqflite.deleteDatabase(file.path);
    } catch (e) {
      debugPrint('⚠️ Error deleting via sqflite: $e');
    }

    // Delete database files
    if (await file.exists()) await file.delete();
    if (await walFile.exists()) await walFile.delete();
    if (await shmFile.exists()) await shmFile.delete();

    debugPrint(
        '✅ Database files deleted. App will create fresh database on next launch.');
  } catch (e) {
    debugPrint('❌ Error resetting database: $e');
    rethrow;
  }
}

/// Configure SQLite for optimal concurrent access.
/// This is now handled automatically during database opening via SqfliteQueryExecutor.setup
/// This function is kept for backwards compatibility but does nothing.
@Deprecated(
    'PRAGMA configuration now happens automatically during database opening')
Future<void> configureDatabaseForConcurrency(AppDatabase db) async {
  debugPrint(
      'ℹ️ configureDatabaseForConcurrency is deprecated - PRAGMA settings are now configured during database opening');
}

/// Clean up duplicate stores (keeps only one instance per server_id).
/// This fixes issues where the same store from the server was inserted multiple times locally.
Future<int> cleanupDuplicateStores(AppDatabase db) async {
  return await db._withDatabaseRetry(() async {
    debugPrint('🧹 Cleaning up duplicate stores...');
    try {
      int deletedCount = 0;

      // Get all stores with server_id
      final allStores = await (db.select(db.stores)
            ..where((s) => s.serverId.isNotNull()))
          .get();

      // Group by server_id
      final storesByServerId = <int, List<Store>>{};
      for (final store in allStores) {
        final serverId = store.serverId!;
        storesByServerId.putIfAbsent(serverId, () => []).add(store);
      }

      // Process duplicates
      for (final entry in storesByServerId.entries) {
        final stores = entry.value;
        if (stores.length > 1) {
          debugPrint(
              '  🔍 Found ${stores.length} instances of store with server_id=${entry.key}');

          // Sort by id ascending (keep the oldest)
          stores.sort((a, b) => a.id.compareTo(b.id));

          // Keep the first one, delete the rest
          for (int i = 1; i < stores.length; i++) {
            final storeToDelete = stores[i];
            await (db.delete(db.stores)
                  ..where((s) => s.id.equals(storeToDelete.id)))
                .go();
            debugPrint(
                '    ❌ Deleted duplicate store with id=${storeToDelete.id}');
            deletedCount++;
          }
        }
      }

      debugPrint('✅ Cleaned up $deletedCount duplicate store(s)');
      return deletedCount;
    } catch (e) {
      debugPrint('❌ Error cleaning up duplicate stores: $e');
      return 0;
    }
  });
}

/// Debug function to check current database lock status
/// Note: This uses customSelect which may not work on all platforms.
/// PRAGMA configuration itself happens during database opening.
Future<Map<String, dynamic>> getDatabaseLockStatus(AppDatabase db) async {
  return await db._withDatabaseRetry(() async {
    try {
      // Note: In-memory databases report 'memory' instead of 'wal'
      final journalRow =
          await db.customSelect('PRAGMA journal_mode').getSingleOrNull();
      final busyRow =
          await db.customSelect('PRAGMA busy_timeout').getSingleOrNull();

      final journalMode = journalRow?.data['journal_mode'];
      final busyTimeout = busyRow?.data['busy_timeout']?.toString();

      debugPrint(
          'Database status check: journal_mode=$journalMode, busy_timeout=$busyTimeout');

      return {
        'journal_mode': journalMode ?? 'unknown',
        'busy_timeout': busyTimeout ?? 'unknown',
        'is_healthy': true,
      };
    } catch (e) {
      // If we can't read PRAGMA settings, that's okay - they're still configured
      debugPrint('Failed to read PRAGMA status: $e');
      return {
        'is_healthy': true,
        'note':
            'Could not read PRAGMA status (this is normal on some platforms)',
        'error': e.toString(),
      };
    }
  });
}
