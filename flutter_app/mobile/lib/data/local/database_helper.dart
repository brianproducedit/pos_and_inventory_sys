import 'dart:convert';
// import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _db;

  // Exposed for tests to inspect the DB instance. Not for production use.
  static Database? get debugDb => _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final path = p.join(docsDir.path, 'pos_app.db');

    try {
      return await openDatabase(path,
          version: 1, onConfigure: _onConfigure, onCreate: _onCreate);
    } catch (e, st) {
      // Defensive: some platform-specific sqlite implementations (Android variations)
      // may attempt to run PRAGMA statements via execSQL and surface a PlatformException
      // referencing `PRAGMA journal_mode = WAL`. If that happens, retry opening the DB
      // with a safe onConfigure that only enables foreign keys to avoid the failing PRAGMA.
      final message = e?.toString() ?? '';
      if (message.contains('PRAGMA journal_mode') ||
          message.contains('journal_mode')) {
        print(
            'Warning: openDatabase failed due to journal_mode PRAGMA: $e\n$st');

        Future<void> _safeOnConfigure(Database db) async {
          try {
            await db.execute('PRAGMA foreign_keys = ON');
          } catch (_) {
            // best-effort; if this also fails, bubble up the original error
          }
        }

        // Retry once with the safe configure handler
        return await openDatabase(path,
            version: 1, onConfigure: _safeOnConfigure, onCreate: _onCreate);
      }

      rethrow;
    }
  }

  Future<void> _onConfigure(Database db) async {
    // Enable foreign keys
    await db.execute('PRAGMA foreign_keys = ON');
    // Improve concurrency and reduce lock contention during tests and CI
    // Use WAL journal mode for better concurrent reads/writes and set a busy timeout
    try {
      // Some PRAGMA statements (notably `journal_mode`) return a result set on some platforms
      // and must be executed with `rawQuery` instead of `execute` to avoid Android execSQL errors.
      final journalRes = await db.rawQuery('PRAGMA journal_mode = WAL');
      if (journalRes.isNotEmpty) {
        try {
          print(
              'DB DEBUG: journal_mode set to ${journalRes.first.values.first}');
        } catch (_) {}
      }
      // busy_timeout may return a result on some drivers; execute it with rawQuery to avoid execSQL errors.
      final busyRes = await db
          .rawQuery('PRAGMA busy_timeout = 5000'); // wait up to 5s for locks
      if (busyRes.isNotEmpty) {
        try {
          print('DB DEBUG: busy_timeout set to ${busyRes.first.values.first}');
        } catch (_) {}
      }
    } catch (e, st) {
      // Some database factories (older drivers) may not support these pragmas; ignore failures
      // but keep a log (including stack trace) to help investigate in CI
      print('Warning: PRAGMA setup failed: $e\n$st');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Users
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        name TEXT,
        email TEXT UNIQUE,
        last_synced INTEGER
      )
    ''');

    // Stores
    await db.execute('''
      CREATE TABLE stores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        name TEXT,
        location TEXT,
        is_active INTEGER DEFAULT 1,
        created_at INTEGER,
        last_updated INTEGER
      )
    ''');

    // Products
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        store_id INTEGER,
        name TEXT,
        sku TEXT UNIQUE,
        price REAL,
        stock_quantity INTEGER,
        is_synced INTEGER DEFAULT 0,
        last_updated INTEGER
      )
    ''');

    // Transactions
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        transaction_number TEXT,
        total_amount REAL,
        payment_method TEXT,
        created_at INTEGER,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    // Transaction items
    await db.execute('''
      CREATE TABLE transaction_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER,
        product_id INTEGER,
        quantity INTEGER,
        price REAL,
        FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
      )
    ''');

    // Sync queue (Transactional Outbox)
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT,
        row_id INTEGER,
        action TEXT,
        payload TEXT,
        created_at INTEGER,
        retry_count INTEGER DEFAULT 0,
        status TEXT DEFAULT 'pending'
      )
    ''');

    // Sync errors
    await db.execute('''
      CREATE TABLE sync_errors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        queue_id INTEGER,
        table_name TEXT,
        row_id INTEGER,
        error TEXT,
        created_at INTEGER
      )
    ''');

    // Sync metadata (key/value) for storing last_server_seq and other small sync metadata
    await db.execute('''
      CREATE TABLE sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  /// Initialize an in-memory database for tests. Call `TestWidgetsFlutterBinding.ensureInitialized()` in tests.
  static Future<void> initTestDb() async {
    final helper = DatabaseHelper._internal();
    _db = await openDatabase(inMemoryDatabasePath,
        version: 1,
        onConfigure: helper._onConfigure,
        onCreate: helper._onCreate);
    // Ensure PRAGMAs for FFI in-memory DB (some drivers may not call onConfigure)
    try {
      final journalRes = await _db!.rawQuery('PRAGMA journal_mode = WAL');
      if (journalRes.isNotEmpty) {
        try {
          print(
              'DB DEBUG: initTestDb journal_mode set to ${journalRes.first.values.first}');
        } catch (_) {}
      }
      final busyRes = await _db!.rawQuery('PRAGMA busy_timeout = 5000');
      if (busyRes.isNotEmpty) {
        try {
          print(
              'DB DEBUG: initTestDb busy_timeout set to ${busyRes.first.values.first}');
        } catch (_) {}
      }
    } catch (e, st) {
      print('Warning: initTestDb PRAGMA setup failed: $e\n$st');
    }
  }

  /// Reset the in-memory test DB (close and clear reference).
  static Future<void> resetTestDb() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  // --- Helper methods ---

  Future<int> insertProduct({
    required String name,
    required String sku,
    double price = 0.0,
    int stockQuantity = 0,
    int? storeId,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.transaction((txn) async {
      final productId = await txn.insert('products', {
        'name': name,
        'sku': sku,
        'price': price,
        'stock_quantity': stockQuantity,
        'store_id': storeId,
        'is_synced': 0,
        'last_updated': now,
      });

      final payload = jsonEncode({
        'table': 'products',
        'row_id': productId,
        'action': 'CREATE',
        'data': {
          'name': name,
          'sku': sku,
          'price': price,
          'stock_quantity': stockQuantity,
          'store_id': storeId
        }
      });

      await txn.insert('sync_queue', {
        'table_name': 'products',
        'row_id': productId,
        'action': 'CREATE',
        'payload': payload,
        'created_at': now,
        'retry_count': 0,
        'status': 'pending'
      });

      return productId;
    });
  }

  /// Insert a store locally and queue a CREATE action
  Future<int> insertStore({
    required String name,
    String? location,
    bool isActive = true,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.transaction((txn) async {
      final storeId = await txn.insert('stores', {
        'name': name,
        'location': location,
        'is_active': isActive ? 1 : 0,
        'created_at': now,
        'last_updated': now,
      });

      final payload = jsonEncode({
        'table': 'stores',
        'row_id': storeId,
        'action': 'CREATE',
        'data': {
          'name': name,
          'location': location,
          'is_active': isActive ? 1 : 0
        }
      });

      await txn.insert('sync_queue', {
        'table_name': 'stores',
        'row_id': storeId,
        'action': 'CREATE',
        'payload': payload,
        'created_at': now,
        'retry_count': 0,
        'status': 'pending'
      });

      return storeId;
    });
  }

  Future<List<Map<String, dynamic>>> getAllStores() async {
    final db = await database;
    return await db.query('stores', orderBy: 'created_at DESC');
  }

  Future<int> updateStore(int localStoreId, Map<String, dynamic> fields) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.transaction((txn) async {
      final updated = await txn.update(
        'stores',
        {...fields, 'last_updated': now},
        where: 'id = ?',
        whereArgs: [localStoreId],
      );

      if (updated == 0) throw Exception('Store not found: $localStoreId');

      final payload = jsonEncode({
        'table': 'stores',
        'row_id': localStoreId,
        'action': 'UPDATE',
        'data': fields
      });

      await txn.insert('sync_queue', {
        'table_name': 'stores',
        'row_id': localStoreId,
        'action': 'UPDATE',
        'payload': payload,
        'created_at': now,
        'retry_count': 0,
        'status': 'pending'
      });

      return updated;
    });
  }

  Future<int> deleteStore(int localStoreId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.transaction((txn) async {
      final deleted = await txn
          .delete('stores', where: 'id = ?', whereArgs: [localStoreId]);

      if (deleted == 0) throw Exception('Store not found: $localStoreId');

      final payload = jsonEncode({
        'table': 'stores',
        'row_id': localStoreId,
        'action': 'DELETE',
      });

      await txn.insert('sync_queue', {
        'table_name': 'stores',
        'row_id': localStoreId,
        'action': 'DELETE',
        'payload': payload,
        'created_at': now,
        'retry_count': 0,
        'status': 'pending'
      });

      return deleted;
    });
  }

  // --- Sync meta helpers ---
  Future<int> getLastServerSeq() async {
    final db = await database;
    final rows = await db
        .query('sync_meta', where: 'key = ?', whereArgs: ['last_server_seq']);
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value']?.toString() ?? '') ?? 0;
  }

  Future<void> setLastServerSeq(int seq) async {
    final db = await database;
    await db.insert(
        'sync_meta', {'key': 'last_server_seq', 'value': seq.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateStock(int localProductId, int newQuantity) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.transaction((txn) async {
      final updated = await txn.update(
        'products',
        {'stock_quantity': newQuantity, 'last_updated': now, 'is_synced': 0},
        where: 'id = ?',
        whereArgs: [localProductId],
      );

      if (updated == 0) throw Exception('Product not found: $localProductId');

      final payload = jsonEncode({
        'table': 'products',
        'row_id': localProductId,
        'action': 'UPDATE',
        'data': {'stock_quantity': newQuantity}
      });

      await txn.insert('sync_queue', {
        'table_name': 'products',
        'row_id': localProductId,
        'action': 'UPDATE',
        'payload': payload,
        'created_at': now,
        'retry_count': 0,
        'status': 'pending'
      });

      return updated;
    });
  }

  /// Update general product fields and queue an UPDATE action
  Future<int> updateProduct(
      int localProductId, Map<String, dynamic> fields) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.transaction((txn) async {
      final updated = await txn.update(
        'products',
        {...fields, 'last_updated': now, 'is_synced': 0},
        where: 'id = ?',
        whereArgs: [localProductId],
      );

      if (updated == 0) throw Exception('Product not found: $localProductId');

      final payload = jsonEncode({
        'table': 'products',
        'row_id': localProductId,
        'action': 'UPDATE',
        'data': fields
      });

      await txn.insert('sync_queue', {
        'table_name': 'products',
        'row_id': localProductId,
        'action': 'UPDATE',
        'payload': payload,
        'created_at': now,
        'retry_count': 0,
        'status': 'pending'
      });

      return updated;
    });
  }

  /// Delete product locally and queue a DELETE action (Transactional Outbox)
  Future<int> deleteProduct(int localProductId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.transaction((txn) async {
      // fetch server_id to include in payload if present
      final rows = await txn
          .query('products', where: 'id = ?', whereArgs: [localProductId]);
      if (rows.isEmpty) {
        // Idempotent: treat missing product as already deleted. Log for diagnostics.
        debugPrint(
            'Warning: deleteProduct: product not found: $localProductId; treating as already deleted');
        return 0;
      }
      final serverId = rows.first['server_id'] as int?;

      // delete the product locally
      final deleted = await txn
          .delete('products', where: 'id = ?', whereArgs: [localProductId]);

      final payload = jsonEncode({
        'table': 'products',
        'row_id': localProductId,
        'action': 'DELETE',
        'data': {'server_id': serverId}
      });

      await txn.insert('sync_queue', {
        'table_name': 'products',
        'row_id': localProductId,
        'action': 'DELETE',
        'payload': payload,
        'created_at': now,
        'retry_count': 0,
        'status': 'pending'
      });

      return deleted;
    });
  }

  Future<int> insertTransaction({
    required String transactionNumber,
    required double totalAmount,
    required String paymentMethod,
    required List<Map<String, dynamic>>
        items, // each: {product_id, quantity, price}
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.transaction((txn) async {
      final txId = await txn.insert('transactions', {
        'transaction_number': transactionNumber,
        'total_amount': totalAmount,
        'payment_method': paymentMethod,
        'created_at': now,
        'is_synced': 0
      });

      for (final it in items) {
        await txn.insert('transaction_items', {
          'transaction_id': txId,
          'product_id': it['product_id'],
          'quantity': it['quantity'],
          'price': it['price']
        });
      }

      final payload = jsonEncode({
        'table': 'transactions',
        'row_id': txId,
        'action': 'CREATE',
        'data': {
          'transaction_number': transactionNumber,
          'total_amount': totalAmount,
          'payment_method': paymentMethod,
          'items': items
        }
      });

      await txn.insert('sync_queue', {
        'table_name': 'transactions',
        'row_id': txId,
        'action': 'CREATE',
        'payload': payload,
        'created_at': now,
        'retry_count': 0,
        'status': 'pending'
      });

      return txId;
    });
  }

  // Query pending sync queue items
  Future<List<Map<String, dynamic>>> getPendingSyncItems(
      {int limit = 100}) async {
    final db = await database;
    final rows = await db.query('sync_queue',
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'created_at ASC',
        limit: limit);
    return rows;
  }

  Future<void> markSyncItemAsSynced(int queueId) async {
    final db = await database;
    await db.update('sync_queue', {'status': 'synced'},
        where: 'id = ?', whereArgs: [queueId]);
  }

  Future<void> incrementRetry(int queueId) async {
    final db = await database;
    await db.rawUpdate(
        'UPDATE sync_queue SET retry_count = retry_count + 1 WHERE id = ?',
        [queueId]);
    final row =
        (await db.query('sync_queue', where: 'id = ?', whereArgs: [queueId]))
            .first;
    final retry = row['retry_count'] as int;
    if (retry >= 5) {
      await db.update('sync_queue', {'status': 'failed'},
          where: 'id = ?', whereArgs: [queueId]);
    }
  }

  Future<void> logSyncError(
      {required int queueId,
      required String tableName,
      required int rowId,
      required String error}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    print('DB DEBUG: logSyncError starting for queue $queueId row $rowId');
    await db.insert('sync_errors', {
      'queue_id': queueId,
      'table_name': tableName,
      'row_id': rowId,
      'error': error,
      'created_at': now
    });
    print('DB DEBUG: logSyncError completed for queue $queueId row $rowId');
  }

  /// Return list of sync error rows ordered by newest first
  Future<List<Map<String, dynamic>>> getSyncErrors({int limit = 100}) async {
    final db = await database;
    final rows =
        await db.query('sync_errors', orderBy: 'created_at DESC', limit: limit);
    return rows;
  }

  /// Remove a single sync error by id
  Future<void> clearSyncError(int id) async {
    final db = await database;
    await db.delete('sync_errors', where: 'id = ?', whereArgs: [id]);
  }

  /// Remove all sync errors associated with a queue item
  Future<void> clearErrorsForQueue(int queueId) async {
    final db = await database;
    await db.delete('sync_errors', where: 'queue_id = ?', whereArgs: [queueId]);
  }

  /// Re-enqueue a failed queue item: reset retry_count and set status to 'pending'
  /// and clear associated sync_errors. Runs inside a transaction.
  Future<void> reenqueueQueueItem(int queueId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawUpdate(
          "UPDATE sync_queue SET retry_count = 0, status = 'pending' WHERE id = ?",
          [queueId]);
      await txn
          .delete('sync_errors', where: 'queue_id = ?', whereArgs: [queueId]);
    });
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
