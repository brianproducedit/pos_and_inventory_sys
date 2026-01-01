import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../local/database_helper.dart';
import 'package:sqflite/sqflite.dart';
import '../remote/postgres_api_service.dart';

class PostgresSyncService {
  final DatabaseHelper db;
  final PostgresApiService api;
  final FlutterSecureStorage secureStorage;
  final http.Client httpClient;
  final Connectivity connectivity;

  /// Lock to prevent concurrent sync operations which can cause database lock issues
  static bool _isSyncing = false;

  PostgresSyncService({
    required this.db,
    required this.api,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
    Connectivity? connectivity,
  })  : secureStorage = secureStorage ?? const FlutterSecureStorage(),
        httpClient = httpClient ?? http.Client(),
        connectivity = connectivity ?? Connectivity();

  /// Acquire the sync lock, returns true if lock acquired, false if already syncing
  static Future<bool> _acquireSyncLock() async {
    if (_isSyncing) {
      debugPrint('PostgresSyncService: Sync already in progress, skipping');
      return false;
    }
    _isSyncing = true;
    return true;
  }

  /// Release the sync lock
  static void _releaseSyncLock() {
    _isSyncing = false;
  }

  Future<bool> syncPendingChanges() async {
    // Prevent concurrent sync operations
    if (!await _acquireSyncLock()) {
      return false;
    }

    try {
      // Check connectivity
      final conn = await connectivity.checkConnectivity();
      if (conn == ConnectivityResult.none) return false;

      // Check token
      final token = await secureStorage.read(key: 'access_token');
      if (token == null) return false;

      final items = await db.getPendingSyncItems();
      if (items.isEmpty) return true;

      for (final item in items) {
        final queueId = item['id'] as int;
        final tableName = item['table_name'] as String;
        final rowId = item['row_id'] as int;
        final action = (item['action'] as String).toUpperCase();
        final payloadJson = item['payload'] as String? ??
            (item['payload_json'] as String? ?? '{}');

        try {
          final payload = jsonDecode(payloadJson) as Map<String, dynamic>;

          // For CREATE/UPDATE we should fetch the latest local data as authoritative
          switch (tableName) {
            case 'products':
              await _syncProduct(queueId, rowId, action, payload, token);
              break;
            case 'stores':
              await _syncStore(queueId, rowId, action, payload, token);
              break;
            case 'transactions':
              await _syncTransaction(queueId, rowId, action, payload, token);
              break;
            case 'users':
              await _syncUser(queueId, rowId, action, payload, token);
              break;
            case 'analytics_events':
              await _syncAnalyticsEvent(queueId, rowId, action, payload, token);
              break;
            case 'settings':
              await _syncSetting(queueId, rowId, action, payload, token);
              break;
            default:
              // Unknown resource; mark failed and log
              await db.logSyncError(
                  queueId: queueId,
                  tableName: tableName,
                  rowId: rowId,
                  error: 'Unknown table');
              await db.incrementRetry(queueId);
              break;
          }
        } catch (e, st) {
          // On any exception, increment retry and capture error
          await db.logSyncError(
              queueId: queueId,
              tableName: tableName,
              rowId: rowId,
              error: e.toString());
          await db.incrementRetry(queueId);
        }
      }

      return true;
    } finally {
      _releaseSyncLock();
    }
  }

  /// Get sync priority for resource types to avoid foreign key violations
  /// Lower number = synced first
  int _getResourcePriority(String? resourceType) {
    switch (resourceType) {
      case 'store':
        return 1; // Stores first (no dependencies)
      case 'product':
        return 2; // Products second (depend on stores)
      case 'user':
        return 3; // Users third (depend on stores)
      case 'transaction':
        return 4; // Transactions fourth (depend on products, users, stores)
      case 'analytics_event':
        return 5; // Analytics events (depend on users, stores)
      case 'setting':
        return 6; // Settings last
      default:
        return 99; // Unknown resources go last
    }
  }

  /// Extract relevant data fields from a local row for sync payload
  Map<String, dynamic> _extractRowDataForSync(
      String tableName, Map<String, dynamic> row) {
    switch (tableName) {
      case 'products':
        return {
          'name': row['name'],
          'sku': row['sku'],
          'price': row['price'],
          'stock_quantity': row['stock_quantity'],
          'store_id': row['store_id'],
        };
      case 'stores':
        return {
          'name': row['name'],
          'location': row['location'],
          'is_active': row['is_active'] == 1,
        };
      case 'users':
        return {
          'username': row['username'],
          'role': row['role'],
          'store_id': row['store_id'],
          'is_active': row['is_active'] == 1,
        };
      case 'transactions':
        return {
          'total_amount': row['total_amount'],
          'payment_method': row['payment_method'],
          'store_id': row['store_id'],
          'user_id': row['user_id'],
        };
      case 'settings':
        return {
          'setting_type': row['setting_type'],
          'key': row['key'],
          'value': row['value'],
          'user_id': row['user_id'],
          'store_id': row['store_id'],
        };
      default:
        // Return all fields excluding internal ones
        final data = Map<String, dynamic>.from(row);
        data.remove('id');
        data.remove('server_id');
        data.remove('is_synced');
        data.remove('last_updated');
        return data;
    }
  }

  /// Batch variant that aggregates pending queue items into a single /api/sync/push
  /// request and applies server responses (id_map, conflicts, applied) atomically.
  /// Uses client_seq for checkpointing to ensure no missed changes on retry.
  Future<bool> syncPendingChangesBatch({int limit = 100}) async {
    // Prevent concurrent sync operations - this is the primary cause of database lock warnings
    if (!await _acquireSyncLock()) {
      return false;
    }

    try {
      // Wrap entire sync operation in try-catch to handle database_closed exceptions
      try {
        // Check connectivity
        final conn = await connectivity.checkConnectivity();
        if (conn == ConnectivityResult.none) {
          debugPrint('syncPendingChangesBatch: No connectivity, skipping push');
          return false;
        }

        // Check token
        final token = await secureStorage.read(key: 'access_token');
        if (token == null) {
          debugPrint('syncPendingChangesBatch: No auth token, skipping push');
          return false;
        }

        // Check database is accessible before starting sync
        try {
          final dbClient = await db.database;
          if (!dbClient.isOpen) {
            debugPrint('syncPendingChangesBatch: Database is closed, skipping');
            return false;
          }
        } catch (e) {
          debugPrint('syncPendingChangesBatch: Database access error: $e');
          return false;
        }

        // Wrap all database operations in try-catch to handle database_closed exceptions
        try {
          final lastPushedSeq = await db.getLastPushedClientSeq();
          final items = await db.getPendingSyncItems(limit: limit);

          debugPrint(
              'syncPendingChangesBatch: Found ${items.length} pending items, lastPushedSeq=$lastPushedSeq');

          if (items.isEmpty) return true;

          // Filter items with client_seq > lastPushedSeq, and assign seq if 0 or stuck
          final dbClient = await db.database;
          int maxSeq = lastPushedSeq;
          final filteredItems = <Map<String, dynamic>>[];
          await dbClient.transaction((txn) async {
            // First, get the current last_client_seq within the transaction
            final seqRows = await txn.query('sync_meta',
                where: 'key = ?', whereArgs: ['last_client_seq']);
            int lastSeq = 0;
            if (seqRows.isNotEmpty) {
              lastSeq =
                  int.tryParse(seqRows.first['value']?.toString() ?? '') ?? 0;
            }

            for (final item in items) {
              final queueId = item['id'] as int;
              int clientSeq = item['client_seq'] as int? ?? 0;

              // Assign new seq if:
              // 1. clientSeq is 0 (never assigned)
              // 2. clientSeq <= lastPushedSeq (stuck item from previous conflict)
              if (clientSeq == 0 || clientSeq <= lastPushedSeq) {
                lastSeq += 1;
                clientSeq = lastSeq;
                await txn.update('sync_queue', {'client_seq': clientSeq},
                    where: 'id = ?', whereArgs: [queueId]);
                debugPrint(
                    'syncPendingChangesBatch: Reassigned seq=$clientSeq to queue item $queueId (was stuck)');
              }

              // Now clientSeq should always be > lastPushedSeq
              if (clientSeq > lastPushedSeq) {
                filteredItems.add({...item, 'client_seq': clientSeq});
                if (clientSeq > maxSeq) maxSeq = clientSeq;
              }
            }

            // Update the last_client_seq in sync_meta
            if (lastSeq > 0) {
              await txn.insert('sync_meta',
                  {'key': 'last_client_seq', 'value': lastSeq.toString()},
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
          });

          if (filteredItems.isEmpty) {
            debugPrint(
                'syncPendingChangesBatch: No items to push (all already pushed or filtered out)');
            return true;
          }

          debugPrint(
              'syncPendingChangesBatch: Filtered to ${filteredItems.length} items to push');

          // Build change set
          final List<Map<String, dynamic>> changes = [];
          final Map<String, int> tempMap = {}; // temp_id -> rowId
          final Map<String, int> queueByTemp = {}; // temp_id -> queueId

          for (final item in filteredItems) {
            final queueId = item['id'] as int;
            final tableName = (item['table_name'] as String)
                .toLowerCase(); // Normalize to lowercase
            final rowId = item['row_id'] as int;
            final action = (item['action'] as String).toUpperCase();
            final payloadJson = item['payload'] as String? ??
                (item['payload_json'] as String? ?? '{}');
            final payload = jsonDecode(payloadJson) as Map<String, dynamic>;

            switch (tableName) {
              case 'products':
                final dbClient = await db.database;
                final rows = await dbClient
                    .query('products', where: 'id = ?', whereArgs: [rowId]);
                final local = rows.isNotEmpty ? rows.first : {};

                final op = action.toLowerCase();
                if (op == 'create' ||
                    (op == 'update' && local['server_id'] == null)) {
                  // send as create with temp_id
                  final tempId = 't${rowId}';
                  tempMap[tempId] = rowId;
                  queueByTemp[tempId] = queueId;
                  changes.add({
                    'resource_type': 'product',
                    'operation': 'create',
                    'temp_id': tempId,
                    'data': payload['data'] ??
                        {
                          'name': local['name'],
                          'sku': local['sku'],
                          'price': local['price'],
                          'stock_quantity': local['stock_quantity'],
                          'store_id': local['store_id']
                        }
                  });
                } else if (op == 'update') {
                  final serverId = local['server_id'] as int?;
                  changes.add({
                    'resource_type': 'product',
                    'operation': 'update',
                    'id': serverId,
                    'data': payload['data'] ??
                        {
                          'name': local['name'],
                          'sku': local['sku'],
                          'price': local['price'],
                          'stock_quantity': local['stock_quantity']
                        },
                    'last_updated': local['last_updated'] != null
                        ? DateTime.fromMillisecondsSinceEpoch(
                                local['last_updated'])
                            .toIso8601String()
                        : null
                  });
                } else if (op == 'delete') {
                  final serverId = local['server_id'] as int?;
                  if (serverId == null) {
                    // local delete: mark as synced locally
                    await db.markSyncItemAsSynced(queueId);
                  } else {
                    changes.add({
                      'resource_type': 'product',
                      'operation': 'delete',
                      'id': serverId
                    });
                  }
                }
                break;
              case 'stores':
                final dbClient = await db.database;
                final rows = await dbClient
                    .query('stores', where: 'id = ?', whereArgs: [rowId]);
                final local = rows.isNotEmpty ? rows.first : {};

                final op = action.toLowerCase();
                if (op == 'create' ||
                    (op == 'update' && local['server_id'] == null)) {
                  // send as create with temp_id
                  final tempId = 't${rowId}';
                  tempMap[tempId] = rowId;
                  queueByTemp[tempId] = queueId;
                  changes.add({
                    'resource_type': 'store',
                    'operation': 'create',
                    'temp_id': tempId,
                    'data': payload['data'] ??
                        {'name': local['name'], 'location': local['location']}
                  });
                } else if (op == 'update') {
                  final serverId = local['server_id'] as int?;
                  changes.add({
                    'resource_type': 'store',
                    'operation': 'update',
                    'id': serverId,
                    'data': payload['data'] ??
                        {
                          'name': local['name'],
                          'location': local['location'],
                          'is_active': local['is_active'] == 1
                        },
                    'last_updated': local['last_updated'] != null
                        ? DateTime.fromMillisecondsSinceEpoch(
                                local['last_updated'])
                            .toIso8601String()
                        : null
                  });
                } else if (op == 'delete') {
                  final serverId = local['server_id'] as int?;
                  if (serverId == null) {
                    // local delete: mark as synced locally
                    await db.markSyncItemAsSynced(queueId);
                  } else {
                    changes.add({
                      'resource_type': 'store',
                      'operation': 'delete',
                      'id': serverId
                    });
                  }
                }
                break;
              case 'analytics_events':
                final dbClient = await db.database;
                final rows = await dbClient.query('analytics_events',
                    where: 'id = ?', whereArgs: [rowId]);
                final local = rows.isNotEmpty ? rows.first : {};

                final op = action.toLowerCase();
                if (op == 'create') {
                  final tempId = 't${rowId}';
                  tempMap[tempId] = rowId;
                  queueByTemp[tempId] = queueId;
                  changes.add({
                    'resource_type': 'analytics_event',
                    'operation': 'create',
                    'temp_id': tempId,
                    'data': payload['data'] ??
                        {
                          'event_name': local['event_name'],
                          'user_id': local['user_id'],
                          'from_store_id': local['from_store_id'],
                          'to_store_id': local['to_store_id'],
                          'duration_ms': local['duration_ms'],
                          'metadata': local['metadata_json'] != null
                              ? jsonDecode(local['metadata_json'])
                              : null,
                          'ip_address': local['ip_address'],
                          'user_agent': local['user_agent'],
                        }
                  });
                }
                // Analytics events are typically not updated or deleted
                break;
              case 'settings':
                final dbClient = await db.database;
                final rows = await dbClient
                    .query('settings', where: 'id = ?', whereArgs: [rowId]);
                final local = rows.isNotEmpty ? rows.first : {};

                final op = action.toLowerCase();
                if (op == 'create' || op == 'update') {
                  final serverId = local['server_id'] as int?;
                  final settingType = local['setting_type'] as String?;
                  final key = local['key'] as String?;
                  final value = local['value'] as String?;

                  if (serverId == null) {
                    // Create new setting
                    final tempId = 't${rowId}';
                    tempMap[tempId] = rowId;
                    queueByTemp[tempId] = queueId;
                    changes.add({
                      'resource_type': 'setting',
                      'operation': 'create',
                      'temp_id': tempId,
                      'data': {
                        'setting_type': settingType,
                        'key': key,
                        'value': value,
                        'user_id': local['user_id'],
                        'store_id': local['store_id'],
                      }
                    });
                  } else {
                    // Update existing setting
                    changes.add({
                      'resource_type': 'setting',
                      'operation': 'update',
                      'id': serverId,
                      'data': {
                        'setting_type': settingType,
                        'key': key,
                        'value': value,
                        'user_id': local['user_id'],
                        'store_id': local['store_id'],
                      }
                    });
                  }
                }
                break;
              case 'transactions':
                try {
                  final dbClient = await db.database;
                  final rows = await dbClient.query('transactions',
                      where: 'id = ?', whereArgs: [rowId]);
                  final local = rows.isNotEmpty ? rows.first : {};

                  final op = action.toLowerCase();
                  if (op == 'create' ||
                      (op == 'update' && local['server_id'] == null)) {
                    final tempId = 't${rowId}';
                    tempMap[tempId] = rowId;
                    queueByTemp[tempId] = queueId;

                    // Get transaction items
                    final itemRows = await dbClient.query('transaction_items',
                        where: 'transaction_id = ?', whereArgs: [rowId]);

                    // Build items array, remapping local product_ids to server_ids or temp_ids
                    final items = <Map<String, dynamic>>[];
                    for (final i in itemRows) {
                      final localProductId = i['product_id'] as int;

                      // Look up the product's server_id
                      final prodRows = await dbClient.query('products',
                          where: 'id = ?', whereArgs: [localProductId]);

                      dynamic productRef;
                      if (prodRows.isNotEmpty) {
                        final prod = prodRows.first;
                        final serverId = prod['server_id'] as int?;

                        if (serverId != null) {
                          // Product has been synced, use server_id
                          productRef = serverId;
                        } else {
                          // Product not yet synced, use temp_id
                          // Check if this product is in the current batch
                          final tempId = 't$localProductId';
                          if (tempMap.containsKey(tempId)) {
                            productRef = tempId;
                          } else {
                            // Product will be synced in a future batch
                            // Skip this transaction for now by throwing an error
                            debugPrint(
                                'syncPendingChangesBatch: Transaction $rowId references unsynced product $localProductId. Deferring transaction sync.');
                            throw Exception(
                                'Transaction references unsynced product');
                          }
                        }
                      } else {
                        // Product doesn't exist locally - data integrity issue
                        debugPrint(
                            'syncPendingChangesBatch: Transaction $rowId references non-existent product $localProductId');
                        throw Exception(
                            'Transaction references non-existent product');
                      }

                      items.add({
                        'product_id': productRef,
                        'quantity': i['quantity'],
                        'unit_price': i['price'],
                        'total_price': (i['quantity'] as int) *
                            ((i['price'] as num).toDouble())
                      });
                    }

                    // Validate all product refs are resolved (not local IDs)
                    for (final item in items) {
                      final productId = item['product_id'];
                      if (productId is int && productId < 100) {
                        // Suspiciously low ID - likely a local ID not server ID
                        debugPrint(
                            'WARNING: Transaction $rowId has suspiciously low product_id=$productId - this may be a local ID');
                      }
                    }

                    // Get store_id and user_id from payload first, then local record, then fallbacks
                    final payloadData =
                        payload['data'] as Map<String, dynamic>?;
                    int? storeId = payloadData?['store_id'] as int? ??
                        local['store_id'] as int?;
                    int? userId = payloadData?['user_id'] as int? ??
                        local['user_id'] as int?;

                    // Fallback for store_id: get from current store in sync_meta if not set
                    if (storeId == null) {
                      final storeRows = await dbClient.query('sync_meta',
                          where: 'key = ?', whereArgs: ['current_store_id']);
                      if (storeRows.isNotEmpty) {
                        storeId = int.tryParse(
                            storeRows.first['value']?.toString() ?? '');
                      }
                    }

                    // Build the data payload, always including store_id and user_id
                    // CRITICAL: Always use the freshly-built 'items' array which has
                    // properly mapped server_ids. NEVER use payloadData['items'] as
                    // that contains raw local product_ids which don't exist on the server!
                    final syncData = {
                      'total_amount':
                          payloadData?['total_amount'] ?? local['total_amount'],
                      'payment_method': payloadData?['payment_method'] ??
                          local['payment_method'],
                      'store_id': storeId,
                      'user_id': userId,
                      'items':
                          items, // Always use mapped items, never payload items!
                    };

                    // Log what we're sending for debugging
                    debugPrint(
                        'syncPendingChangesBatch: Transaction $rowId sending ${items.length} items with product_ids: ${items.map((i) => i['product_id']).toList()}');

                    changes.add({
                      'resource_type': 'transaction',
                      'operation': 'create',
                      'temp_id': tempId,
                      'data': syncData,
                    });
                  } else if (op == 'update') {
                    final serverId = local['server_id'] as int?;
                    changes.add({
                      'resource_type': 'transaction',
                      'operation': 'update',
                      'id': serverId,
                      'data': payload['data'] ??
                          {
                            'total_amount': local['total_amount'],
                            'payment_method': local['payment_method'],
                            'status': local['status'],
                          }
                    });
                  }
                } catch (e) {
                  // Transaction has unmet dependencies (unsynced products)
                  // Skip it in this batch - it will retry in the next sync
                  debugPrint(
                      'syncPendingChangesBatch: Skipping transaction $rowId due to dependencies: $e');
                  // Don't add to changes list, but don't mark as error either
                }
                break;
              case 'users':
                final dbClient = await db.database;
                final rows = await dbClient
                    .query('users', where: 'id = ?', whereArgs: [rowId]);
                final local = rows.isNotEmpty ? rows.first : {};

                final op = action.toLowerCase();
                if (op == 'create' ||
                    (op == 'update' && local['server_id'] == null)) {
                  final tempId = 't${rowId}';
                  tempMap[tempId] = rowId;
                  queueByTemp[tempId] = queueId;
                  changes.add({
                    'resource_type': 'user',
                    'operation': 'create',
                    'temp_id': tempId,
                    'data': payload['data'] ??
                        {
                          'username': local['username'],
                          'role': local['role'],
                          'store_id': local['store_id'],
                          'is_active': local['is_active'] == 1,
                        }
                  });
                } else if (op == 'update') {
                  final serverId = local['server_id'] as int?;
                  changes.add({
                    'resource_type': 'user',
                    'operation': 'update',
                    'id': serverId,
                    'data': payload['data'] ??
                        {
                          'username': local['username'],
                          'role': local['role'],
                          'store_id': local['store_id'],
                          'is_active': local['is_active'] == 1,
                        }
                  });
                } else if (op == 'delete') {
                  final serverId = local['server_id'] as int?;
                  if (serverId != null) {
                    changes.add({
                      'resource_type': 'user',
                      'operation': 'delete',
                      'id': serverId
                    });
                  } else {
                    await db.markSyncItemAsSynced(queueId);
                  }
                }
                break;
              default:
                // Check if this is truly an unknown table or just an orphaned record
                // For certain errors, mark as synced to avoid infinite retry loops
                debugPrint(
                    'syncPendingChangesBatch: Unknown or unsupported table "$tableName" for queue item $queueId');

                // If this item has been retried multiple times, mark it as synced instead of continuing to retry
                final retryCount = item['retry_count'] as int? ?? 0;
                if (retryCount >= 3) {
                  debugPrint(
                      'syncPendingChangesBatch: Marking queue item $queueId as synced after $retryCount failed retries (unknown table)');
                  await db.markSyncItemAsSynced(queueId);
                } else {
                  // Log error and increment retry for first few attempts
                  await db.logSyncError(
                      queueId: queueId,
                      tableName: tableName,
                      rowId: rowId,
                      error: 'Unknown table in batch: $tableName');
                  await db.incrementRetry(queueId);
                }
            }
          }

          if (changes.isEmpty) {
            debugPrint(
                'syncPendingChangesBatch: No changes built, returning true');
            return true;
          }

          // Sort changes by dependency order to avoid foreign key violations
          // Priority: 1=stores, 2=products, 3=users, 4=transactions, 5=others
          changes.sort((a, b) {
            final aPriority =
                _getResourcePriority(a['resource_type'] as String?);
            final bPriority =
                _getResourcePriority(b['resource_type'] as String?);
            return aPriority.compareTo(bPriority);
          });

          debugPrint(
              'syncPendingChangesBatch: Pushing ${changes.length} changes to server (sorted by dependency)');

          try {
            final res = await api.pushChangesBatch(changes, token: token);
            debugPrint(
                'syncPendingChangesBatch: Push successful, processing response');

            final idMap =
                (res['id_map'] as Map?)?.cast<String, dynamic>() ?? {};
            final conflicts = (res['conflicts'] as List?) ?? [];
            final applied = (res['applied'] as List?) ?? [];

            final dbClient = await db.database;
            // Apply id_map: update local rows and mark queue items synced
            await dbClient.transaction((txn) async {
              for (final entry in idMap.entries) {
                final tempId = entry.key;
                final serverId = entry.value as int;
                final rowId = tempMap[tempId];
                if (rowId != null) {
                  final now = DateTime.now().millisecondsSinceEpoch;
                  await txn.update(
                      'products',
                      {
                        'server_id': serverId,
                        'is_synced': 1,
                        'last_updated': now
                      },
                      where: 'id = ?',
                      whereArgs: [rowId]);
                  final qid = queueByTemp[tempId];
                  if (qid != null) {
                    await txn.update('sync_queue', {'status': 'synced'},
                        where: 'id = ?', whereArgs: [qid]);
                  }
                }
              }

              // Handle applied updates/deletes by matching server id in changes: update or delete local rows and mark corresponding queue items as synced
              for (final a in applied) {
                final resource = a['resource_type'] as String?;
                final op = (a['operation'] as String?)?.toLowerCase();
                final id = a['id'] as int?;
                if (resource == 'product' && id != null) {
                  final now = DateTime.now().millisecondsSinceEpoch;
                  if (op == 'delete') {
                    // Delete any local products that have this server_id and mark their queue items as synced
                    final rows = await txn.query('products',
                        where: 'server_id = ?', whereArgs: [id]);
                    for (final r in rows) {
                      final rowId = r['id'] as int;
                      await txn.delete('products',
                          where: 'id = ?', whereArgs: [rowId]);
                      await txn.update('sync_queue', {'status': 'synced'},
                          where: 'row_id = ?', whereArgs: [rowId]);
                    }
                  } else if (op == 'update' || op == 'create') {
                    // If server provided authoritative data for this resource, apply it to
                    // local rows; otherwise, at minimum mark rows with matching server_id
                    // as synced and update last_updated.
                    final data = (a['data'] as Map?)?.cast<String, dynamic>();

                    final updateFields = <String, Object>{
                      'is_synced': 1,
                      'last_updated': now
                    };
                    if (data != null && data.isNotEmpty) {
                      // Apply only known product fields to avoid injecting unknown keys
                      if (data.containsKey('name'))
                        updateFields['name'] = data['name'] as Object;
                      if (data.containsKey('sku'))
                        updateFields['sku'] = data['sku'] as Object;
                      if (data.containsKey('price'))
                        updateFields['price'] = data['price'] as Object;
                      if (data.containsKey('stock_quantity'))
                        updateFields['stock_quantity'] =
                            data['stock_quantity'] as Object;
                      if (data.containsKey('store_id'))
                        updateFields['store_id'] = data['store_id'] as Object;
                    }

                    await txn.update('products', updateFields,
                        where: 'server_id = ?', whereArgs: [id]);

                    // Mark any queue items that reference those product rows as synced
                    final matched = await txn.query('products',
                        where: 'server_id = ?', whereArgs: [id]);
                    for (final m in matched) {
                      await txn.update('sync_queue', {'status': 'synced'},
                          where: 'row_id = ?', whereArgs: [m['id']]);
                    }
                  }
                } else if (resource == 'store' && id != null) {
                  final now = DateTime.now().millisecondsSinceEpoch;
                  if (op == 'delete') {
                    // Delete any local stores that have this server_id and mark their queue items as synced
                    final rows = await txn.query('stores',
                        where: 'server_id = ?', whereArgs: [id]);
                    for (final r in rows) {
                      final rowId = r['id'] as int;
                      await txn.delete('stores',
                          where: 'id = ?', whereArgs: [rowId]);
                      await txn.update('sync_queue', {'status': 'synced'},
                          where: 'row_id = ?', whereArgs: [rowId]);
                    }
                  } else if (op == 'update' || op == 'create') {
                    // If server provided authoritative data for this resource, apply it to
                    // local rows; otherwise, at minimum mark rows with matching server_id
                    // as synced and update last_updated.
                    final data = (a['data'] as Map?)?.cast<String, dynamic>();

                    final updateFields = <String, Object>{
                      'is_synced': 1,
                      'last_updated': now
                    };
                    if (data != null && data.isNotEmpty) {
                      // Apply only known store fields to avoid injecting unknown keys
                      if (data.containsKey('name'))
                        updateFields['name'] = data['name'] as Object;
                      if (data.containsKey('location'))
                        updateFields['location'] = data['location'] as Object;
                      if (data.containsKey('is_active'))
                        updateFields['is_active'] =
                            (data['is_active'] as bool ? 1 : 0);
                    }

                    await txn.update('stores', updateFields,
                        where: 'server_id = ?', whereArgs: [id]);

                    // Mark any queue items that reference those store rows as synced
                    final matched = await txn.query('stores',
                        where: 'server_id = ?', whereArgs: [id]);
                    for (final m in matched) {
                      await txn.update('sync_queue', {'status': 'synced'},
                          where: 'row_id = ?', whereArgs: [m['id']]);
                    }
                  }
                } else if (resource == 'analytics_event' && id != null) {
                  // Analytics events are typically not updated/deleted from server
                  // Just mark as synced
                  final matched = await txn.query('analytics_events',
                      where: 'server_id = ?', whereArgs: [id]);
                  for (final m in matched) {
                    await txn.update('sync_queue', {'status': 'synced'},
                        where: 'row_id = ?', whereArgs: [m['id']]);
                  }
                } else if (resource == 'setting' && id != null) {
                  final now = DateTime.now().millisecondsSinceEpoch;
                  if (op == 'delete') {
                    // Delete local settings with this server_id
                    final rows = await txn.query('settings',
                        where: 'server_id = ?', whereArgs: [id]);
                    for (final r in rows) {
                      final rowId = r['id'] as int;
                      await txn.delete('settings',
                          where: 'id = ?', whereArgs: [rowId]);
                      await txn.update('sync_queue', {'status': 'synced'},
                          where: 'row_id = ?', whereArgs: [rowId]);
                    }
                  } else if (op == 'update' || op == 'create') {
                    // Update local settings
                    final data = (a['data'] as Map?)?.cast<String, dynamic>();
                    if (data != null) {
                      final updateFields = <String, Object>{
                        'is_synced': 1,
                        'updated_at': now
                      };
                      if (data.containsKey('value'))
                        updateFields['value'] = data['value'] as Object;

                      await txn.update('settings', updateFields,
                          where: 'server_id = ?', whereArgs: [id]);

                      // Mark queue items as synced
                      final matched = await txn.query('settings',
                          where: 'server_id = ?', whereArgs: [id]);
                      for (final m in matched) {
                        await txn.update('sync_queue', {'status': 'synced'},
                            where: 'row_id = ?', whereArgs: [m['id']]);
                      }
                    }
                  }
                }
              }

              // Record conflicts
              for (final c in conflicts) {
                final table = c['resource_type'] ?? 'unknown';
                final id = c['id'] ?? -1;
                final message = c['message'] ?? c.toString();

                // Log conflict details for debugging
                debugPrint(
                    'syncPendingChangesBatch: CONFLICT - resource=$table, id=$id, message=$message');
                debugPrint(
                    'syncPendingChangesBatch: Full conflict data: ${c.toString()}');

                // Special handling for "Server record not found" - these are orphaned references
                // that won't be resolved by retrying, so mark them as synced to avoid infinite loops
                final isServerRecordNotFound = message
                    .toString()
                    .toLowerCase()
                    .contains('server record not found');

                if (isServerRecordNotFound) {
                  debugPrint(
                      'syncPendingChangesBatch: Detected orphaned reference (server record not found), marking as synced');

                  // Map resource_type to table_name (server uses singular, local uses plural)
                  final tableNameMap = {
                    'product': 'products',
                    'store': 'stores',
                    'user': 'users',
                    'transaction': 'transactions',
                    'setting': 'settings',
                    'analytics_event': 'analytics_events',
                  };
                  final localTableName = tableNameMap[table] ?? table;

                  // The conflict id is the SERVER id, not the local row_id
                  // We need to find the local product with this server_id and get its local id
                  final serverId = id as int?;
                  List<Map<String, dynamic>> matchingRows = [];
                  int? localRowId;

                  if (serverId != null && serverId > 0) {
                    // First find the local row that has this server_id
                    final localRows = await txn.query(localTableName,
                        where: 'server_id = ?', whereArgs: [serverId]);

                    if (localRows.isNotEmpty) {
                      localRowId = localRows.first['id'] as int;
                      // Now find the sync_queue item with this local row_id
                      matchingRows = await txn.query('sync_queue',
                          where: 'table_name = ? AND row_id = ? AND status = ?',
                          whereArgs: [localTableName, localRowId, 'pending']);

                      debugPrint(
                          'syncPendingChangesBatch: Found local row $localRowId with server_id=$serverId, found ${matchingRows.length} pending queue items');

                      // Clear the server_id from the local row since it's orphaned
                      // This allows future updates to be sent as CREATE instead of UPDATE
                      await txn.update(
                          localTableName, {'server_id': null, 'is_synced': 0},
                          where: 'id = ?', whereArgs: [localRowId]);
                      debugPrint(
                          'syncPendingChangesBatch: Cleared orphaned server_id from local $localTableName row $localRowId');

                      // Queue a CREATE operation to re-sync this item to the server immediately
                      // This ensures the data gets back on the server without waiting for next edit
                      final now = DateTime.now().millisecondsSinceEpoch;
                      final nextSeq = await db.getNextClientSeqWithTxn(txn);

                      // Get the current data from the local row
                      final rowData = localRows.first;
                      final payload = {
                        'table': localTableName,
                        'row_id': localRowId,
                        'action': 'CREATE',
                        'data': _extractRowDataForSync(localTableName, rowData)
                      };

                      await txn.insert('sync_queue', {
                        'table_name': localTableName,
                        'row_id': localRowId,
                        'action': 'CREATE',
                        'payload': jsonEncode(payload),
                        'created_at': now,
                        'retry_count': 0,
                        'status': 'pending',
                        'client_seq': nextSeq,
                      });

                      debugPrint(
                          'syncPendingChangesBatch: Queued CREATE operation for $localTableName row $localRowId to re-sync to server');
                    } else {
                      debugPrint(
                          'syncPendingChangesBatch: No local row found with server_id=$serverId');
                    }
                  }

                  // Fallback: if no matching rows found via server_id lookup, try direct match
                  if (matchingRows.isEmpty) {
                    matchingRows = await txn.query('sync_queue',
                        where: 'table_name = ? AND status = ?',
                        whereArgs: [localTableName, 'pending']);
                    debugPrint(
                        'syncPendingChangesBatch: Fallback query found ${matchingRows.length} pending items for $localTableName');
                  }

                  for (final qr in matchingRows) {
                    await txn.update('sync_queue', {'status': 'synced'},
                        where: 'id = ?', whereArgs: [qr['id']]);

                    // Don't log orphaned references to sync_errors table since they're
                    // automatically resolved (server_id cleared, CREATE queued).
                    // This avoids cluttering the error list with non-actionable items.
                    debugPrint(
                        'syncPendingChangesBatch: Marked queue item ${qr['id']} as synced (orphaned $table id=$id) - auto-resolved');
                  }
                  continue; // Skip normal retry logic for this conflict
                }

                // Normal conflict handling: increment retry count
                final qrows = await txn.query('sync_queue',
                    where: 'status = ?', whereArgs: ['pending']);
                for (final qr in qrows) {
                  final currentRetryCount = qr['retry_count'] as int;

                  await txn.insert('sync_errors', {
                    'queue_id': qr['id'],
                    'table_name': table,
                    'row_id': qr['row_id'],
                    'error': message,
                    'created_at': DateTime.now().millisecondsSinceEpoch
                  });

                  // Increment retry count and assign new client_seq so it will be retried
                  final newRetryCount = currentRetryCount + 1;
                  final newClientSeq = await db.getNextClientSeqWithTxn(txn);

                  await txn.update(
                      'sync_queue',
                      {
                        'retry_count': newRetryCount,
                        'client_seq': newClientSeq
                      },
                      where: 'id = ?',
                      whereArgs: [qr['id']]);

                  // If retry limit exceeded, mark as failed
                  if (newRetryCount >= 5) {
                    await txn.update('sync_queue', {'status': 'failed'},
                        where: 'id = ?', whereArgs: [qr['id']]);
                    debugPrint(
                        'syncPendingChangesBatch: Queue item ${qr['id']} marked as failed after $newRetryCount retries');
                  } else {
                    debugPrint(
                        'syncPendingChangesBatch: Queue item ${qr['id']} will retry with new seq=$newClientSeq (retry $newRetryCount/5)');
                  }
                }
              }
            });

            // Update checkpoint: mark these changes as pushed
            await db.setLastPushedClientSeq(maxSeq);

            debugPrint(
                'syncPendingChangesBatch: Completed successfully. Checkpoint updated to seq=$maxSeq');
            debugPrint(
                'syncPendingChangesBatch: Applied ${applied.length} changes, ${conflicts.length} conflicts, ${idMap.length} id mappings');

            return true;
          } catch (e) {
            debugPrint('syncPendingChangesBatch: Push failed with error: $e');
            // On HTTP or parse exceptions, increment retry for all queued items
            for (final item in items) {
              await db.incrementRetry(item['id'] as int);
            }
            return true; // non-fatal
          }
        } on PlatformException catch (e) {
          // Handle database_closed exceptions (common during hot reload or app shutdown)
          if (e.message?.contains('database_closed') == true) {
            debugPrint(
                'syncPendingChangesBatch: Database closed during sync (expected during hot reload)');
          } else {
            debugPrint(
                'syncPendingChangesBatch: Platform exception: ${e.message}');
          }
          return false;
        } catch (e, stackTrace) {
          debugPrint('syncPendingChangesBatch: Unexpected error: $e');
          debugPrint('Stack trace: $stackTrace');
          return false;
        }
      } catch (e, stackTrace) {
        // Outermost catch for any unhandled exceptions from the initial setup
        debugPrint('syncPendingChangesBatch: Fatal error: $e');
        debugPrint('Stack trace: $stackTrace');
        return false;
      }
    } finally {
      _releaseSyncLock();
    }
  }

  /// Pull changes from the server since the given timestamp and apply to local DB.
  /// This mirrors the behaviour expected by syncUsing and is non-fatal.
  Future<void> pullChangesSinceSeq() async {
    try {
      final token = await secureStorage.read(key: 'access_token');
      if (token == null) return;

      // Check database is accessible
      final dbClient = await db.database;
      if (!dbClient.isOpen) {
        debugPrint('pullChangesSinceSeq: Database is closed, skipping');
        return;
      }

      final lastSeq = await db.getLastServerSeq();
      final res = await api.fetchChangesSinceSeq(lastSeq, token: token);
      final changes =
          (res['changes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final headSeq = res['head_seq'] as int? ?? lastSeq;

      if (changes.isEmpty) {
        await db.setLastServerSeq(headSeq);
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      await dbClient.transaction((txn) async {
        for (final ch in changes) {
          final entityType = ch['entity_type'] as String?;
          final entityId = ch['entity_id']?.toString();
          final op = ch['operation'] as String?;
          final payload = ch['payload'] is Map
              ? Map<String, dynamic>.from(ch['payload'] as Map)
              : <String, dynamic>{};

          if (entityType == 'product') {
            if (op == 'create' || op == 'update') {
              // If server provided an id, try to update or insert by server_id
              final serverId = int.tryParse(entityId ?? '');
              final data = payload['data'] as Map<String, dynamic>? ?? {};
              final map = <String, Object?>{
                'server_id': serverId,
                'store_id': data['store_id'],
                'name': data['name'],
                'sku': data['sku'],
                'price': data['price'],
                'stock_quantity': data['stock_quantity'],
                'is_synced': 1,
                'last_updated': now
              };
              if (serverId != null) {
                final rows = await txn.query('products',
                    where: 'server_id = ?', whereArgs: [serverId]);
                if (rows.isEmpty) {
                  await txn.insert('products', map);
                } else {
                  await txn.update('products', map,
                      where: 'server_id = ?', whereArgs: [serverId]);
                }
              } else {
                // No server id provided; skip or try best-effort match by sku
                final sku = data['sku'] as String?;
                if (sku != null) {
                  final r = await txn
                      .query('products', where: 'sku = ?', whereArgs: [sku]);
                  if (r.isEmpty) {
                    await txn.insert('products', map);
                  } else {
                    await txn.update('products', map,
                        where: 'sku = ?', whereArgs: [sku]);
                  }
                }
              }
            } else if (op == 'delete') {
              final serverId = int.tryParse(entityId ?? '');
              if (serverId != null) {
                final rows = await txn.query('products',
                    where: 'server_id = ?', whereArgs: [serverId]);
                for (final r in rows) {
                  await txn.delete('products',
                      where: 'id = ?', whereArgs: [r['id']]);
                }
              }
            }
          } else if (entityType == 'store') {
            if (op == 'create' || op == 'update') {
              final serverId = int.tryParse(entityId ?? '');
              final data = payload['data'] as Map<String, dynamic>? ?? {};
              final map = <String, Object?>{
                'server_id': serverId,
                'name': data['name'],
                'location': data['location'],
                'is_active': data['is_active'] == true ? 1 : 0,
                'created_at': now,
                'last_updated': now
              };
              if (serverId != null) {
                final rows = await txn.query('stores',
                    where: 'server_id = ?', whereArgs: [serverId]);
                if (rows.isEmpty) {
                  await txn.insert('stores', map);
                } else {
                  await txn.update('stores', map,
                      where: 'server_id = ?', whereArgs: [serverId]);
                }
              }
            } else if (op == 'delete') {
              final serverId = int.tryParse(entityId ?? '');
              if (serverId != null) {
                final rows = await txn.query('stores',
                    where: 'server_id = ?', whereArgs: [serverId]);
                for (final r in rows) {
                  await txn
                      .delete('stores', where: 'id = ?', whereArgs: [r['id']]);
                }
              }
            }
          } else if (entityType == 'user') {
            if (op == 'create' || op == 'update') {
              final serverId = int.tryParse(entityId ?? '');
              final data = payload['data'] as Map<String, dynamic>? ?? {};
              final map = <String, Object?>{
                'server_id': serverId,
                'username': data['username'],
                'name': data['name'],
                'email': data['email'],
                'role': data['role'],
                'store_id': data['store_id'],
                'is_active': data['is_active'] == true ? 1 : 0,
                'last_updated': now
              };
              if (serverId != null) {
                final rows = await txn.query('users',
                    where: 'server_id = ?', whereArgs: [serverId]);
                if (rows.isEmpty) {
                  await txn.insert('users', map);
                } else {
                  await txn.update('users', map,
                      where: 'server_id = ?', whereArgs: [serverId]);
                }
              }
            } else if (op == 'delete') {
              final serverId = int.tryParse(entityId ?? '');
              if (serverId != null) {
                final rows = await txn.query('users',
                    where: 'server_id = ?', whereArgs: [serverId]);
                for (final r in rows) {
                  await txn
                      .delete('users', where: 'id = ?', whereArgs: [r['id']]);
                }
              }
            }
          } else if (entityType == 'analytics_event') {
            // Analytics events are typically not pulled from server (they're sent to server)
            // But if we receive them, we can store them locally for caching
            if (op == 'create') {
              final serverId = int.tryParse(entityId ?? '');
              final data = payload['data'] as Map<String, dynamic>? ?? {};
              final map = <String, Object?>{
                'server_id': serverId,
                'event_name': data['event_name'],
                'user_id': data['user_id'],
                'from_store_id': data['from_store_id'],
                'to_store_id': data['to_store_id'],
                'duration_ms': data['duration_ms'],
                'metadata_json': data['metadata'] != null
                    ? jsonEncode(data['metadata'])
                    : null,
                'ip_address': data['ip_address'],
                'user_agent': data['user_agent'],
                'created_at': data['created_at'] != null
                    ? DateTime.parse(data['created_at']).millisecondsSinceEpoch
                    : now,
                'is_synced': 1,
              };
              if (serverId != null) {
                final rows = await txn.query('analytics_events',
                    where: 'server_id = ?', whereArgs: [serverId]);
                if (rows.isEmpty) {
                  await txn.insert('analytics_events', map);
                } else {
                  await txn.update('analytics_events', map,
                      where: 'server_id = ?', whereArgs: [serverId]);
                }
              }
            }
          } else if (entityType == 'setting') {
            if (op == 'create' || op == 'update') {
              final serverId = int.tryParse(entityId ?? '');
              final data = payload['data'] as Map<String, dynamic>? ?? {};
              final map = <String, Object?>{
                'server_id': serverId,
                'setting_type': data['setting_type'],
                'key': data['key'],
                'value': data['value'],
                'user_id': data['user_id'],
                'store_id': data['store_id'],
                'created_at': now,
                'updated_at': now,
                'is_synced': 1,
              };
              if (serverId != null) {
                final rows = await txn.query('settings',
                    where: 'server_id = ?', whereArgs: [serverId]);
                if (rows.isEmpty) {
                  await txn.insert('settings', map);
                } else {
                  await txn.update('settings', map,
                      where: 'server_id = ?', whereArgs: [serverId]);
                }
              }
            } else if (op == 'delete') {
              final serverId = int.tryParse(entityId ?? '');
              if (serverId != null) {
                final rows = await txn.query('settings',
                    where: 'server_id = ?', whereArgs: [serverId]);
                for (final r in rows) {
                  await txn.delete('settings',
                      where: 'id = ?', whereArgs: [r['id']]);
                }
              }
            }
          }
          // TODO: handle other entity types as needed
        }

        // Commit head seq (atomic with changes applied)
        await txn.insert('sync_meta',
            {'key': 'last_server_seq', 'value': headSeq.toString()},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });

      // Clean up orphaned products that have never been synced
      await db.cleanupOrphanedProducts();
    } on PlatformException catch (e) {
      if (e.message?.contains('database_closed') == true) {
        debugPrint(
            'pullChangesSinceSeq: Database closed during pull (expected during hot reload)');
      } else {
        debugPrint('pullChangesSinceSeq: Platform exception: ${e.message}');
      }
    } catch (e, stackTrace) {
      debugPrint('pullChangesSinceSeq: Error pulling changes: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> _syncProduct(int queueId, int rowId, String action,
      Map<String, dynamic> payload, String token) async {
    // Fetch local product
    final dbClient = await db.database;
    final rows =
        await dbClient.query('products', where: 'id = ?', whereArgs: [rowId]);
    if (rows.isEmpty) {
      // Nothing to sync; mark queue item as failed
      await db.logSyncError(
          queueId: queueId,
          tableName: 'products',
          rowId: rowId,
          error: 'Local product not found');
      await db.incrementRetry(queueId);
      return;
    }
    final product = rows.first;

    try {
      if (action == 'CREATE') {
        final body = jsonEncode({
          'name': product['name'],
          'sku': product['sku'],
          'price': product['price'],
          'stock_quantity': product['stock_quantity']
        });
        final res = await httpClient.post(
            Uri.parse(api.baseUrl + '/api/products'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: body);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final serverId = data['id'] as int?;
          // Update local product and mark queue as synced in a single transaction
          final now = DateTime.now().millisecondsSinceEpoch;
          final tx = await dbClient.transaction((txn) async {
            await txn.update('products',
                {'server_id': serverId, 'is_synced': 1, 'last_updated': now},
                where: 'id = ?', whereArgs: [rowId]);
            await txn.update('sync_queue', {'status': 'synced'},
                where: 'id = ?', whereArgs: [queueId]);
          });
        } else if (res.statusCode == 409) {
          await db.logSyncError(
              queueId: queueId,
              tableName: 'products',
              rowId: rowId,
              error: 'Conflict: ${res.body}');
          // Mark failed
          await db.incrementRetry(queueId);
        } else {
          await db.logSyncError(
              queueId: queueId,
              tableName: 'products',
              rowId: rowId,
              error: 'HTTP ${res.statusCode}: ${res.body}');
          await db.incrementRetry(queueId);
        }
      } else if (action == 'UPDATE') {
        // Prefer server_id when available
        final serverId = product['server_id'] as int?;
        final body = jsonEncode({
          'name': product['name'],
          'sku': product['sku'],
          'price': product['price'],
          'stock_quantity': product['stock_quantity']
        });
        if (serverId == null) {
          // If we don't have server id, attempt create instead
          final res = await httpClient.post(
              Uri.parse(api.baseUrl + '/api/products'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json'
              },
              body: body);
          if (res.statusCode >= 200 && res.statusCode < 300) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final assigned = data['id'] as int?;
            final now = DateTime.now().millisecondsSinceEpoch;
            await dbClient.transaction((txn) async {
              await txn.update('products',
                  {'server_id': assigned, 'is_synced': 1, 'last_updated': now},
                  where: 'id = ?', whereArgs: [rowId]);
              await txn.update('sync_queue', {'status': 'synced'},
                  where: 'id = ?', whereArgs: [queueId]);
            });
          } else {
            await db.logSyncError(
                queueId: queueId,
                tableName: 'products',
                rowId: rowId,
                error: 'Create fallback failed: ${res.body}');
            await db.incrementRetry(queueId);
          }
        } else {
          final res = await httpClient.put(
              Uri.parse(api.baseUrl + '/api/products/$serverId'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json'
              },
              body: body);
          if (res.statusCode >= 200 && res.statusCode < 300) {
            final now = DateTime.now().millisecondsSinceEpoch;
            await dbClient.transaction((txn) async {
              await txn.update(
                  'products', {'is_synced': 1, 'last_updated': now},
                  where: 'id = ?', whereArgs: [rowId]);
              await txn.update('sync_queue', {'status': 'synced'},
                  where: 'id = ?', whereArgs: [queueId]);
            });
          } else if (res.statusCode == 409) {
            await db.logSyncError(
                queueId: queueId,
                tableName: 'products',
                rowId: rowId,
                error: 'Conflict: ${res.body}');
            await db.incrementRetry(queueId);
          } else {
            await db.logSyncError(
                queueId: queueId,
                tableName: 'products',
                rowId: rowId,
                error: 'HTTP ${res.statusCode}: ${res.body}');
            await db.incrementRetry(queueId);
          }
        }
      } else if (action == 'DELETE') {
        final serverId = product['server_id'] as int?;
        if (serverId == null) {
          // If server id unknown, just delete the local product and mark queue as synced
          final now = DateTime.now().millisecondsSinceEpoch;
          await dbClient.transaction((txn) async {
            await txn.delete('products', where: 'id = ?', whereArgs: [rowId]);
            await txn.update('sync_queue', {'status': 'synced'},
                where: 'id = ?', whereArgs: [queueId]);
          });
        } else {
          final res = await httpClient.delete(
              Uri.parse(api.baseUrl + '/api/products/$serverId'),
              headers: {'Authorization': 'Bearer $token'});
          if (res.statusCode >= 200 && res.statusCode < 300) {
            final now = DateTime.now().millisecondsSinceEpoch;
            await dbClient.transaction((txn) async {
              await txn.delete('products', where: 'id = ?', whereArgs: [rowId]);
              await txn.update('sync_queue', {'status': 'synced'},
                  where: 'id = ?', whereArgs: [queueId]);
            });
          } else {
            await db.logSyncError(
                queueId: queueId,
                tableName: 'products',
                rowId: rowId,
                error: 'Delete failed: ${res.body}');
            await db.incrementRetry(queueId);
          }
        }
      }
    } catch (e) {
      await db.logSyncError(
          queueId: queueId,
          tableName: 'products',
          rowId: rowId,
          error: e.toString());
      await db.incrementRetry(queueId);
    }
  }

  Future<void> _syncStore(int queueId, int rowId, String action,
      Map<String, dynamic> payload, String token) async {
    // Fetch local store
    final dbClient = await db.database;
    final rows =
        await dbClient.query('stores', where: 'id = ?', whereArgs: [rowId]);
    if (rows.isEmpty) {
      // Nothing to sync; mark queue item as failed
      await db.logSyncError(
          queueId: queueId,
          tableName: 'stores',
          rowId: rowId,
          error: 'Local store not found');
      await db.incrementRetry(queueId);
      return;
    }
    final store = rows.first;

    try {
      if (action == 'CREATE') {
        final body =
            jsonEncode({'name': store['name'], 'location': store['location']});
        final res = await httpClient.post(
            Uri.parse(api.baseUrl + '/api/stores'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: body);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final serverId = data['id'] as int?;
          // Update local store and mark queue as synced in a single transaction
          final now = DateTime.now().millisecondsSinceEpoch;
          final tx = await dbClient.transaction((txn) async {
            await txn.update('stores',
                {'server_id': serverId, 'is_synced': 1, 'last_updated': now},
                where: 'id = ?', whereArgs: [rowId]);
            await txn.update('sync_queue', {'status': 'synced'},
                where: 'id = ?', whereArgs: [queueId]);
          });
        } else if (res.statusCode == 409) {
          await db.logSyncError(
              queueId: queueId,
              tableName: 'stores',
              rowId: rowId,
              error: 'Conflict: ${res.body}');
          // Mark failed
          await db.incrementRetry(queueId);
        } else {
          await db.logSyncError(
              queueId: queueId,
              tableName: 'stores',
              rowId: rowId,
              error: 'HTTP ${res.statusCode}: ${res.body}');
          await db.incrementRetry(queueId);
        }
      } else if (action == 'UPDATE') {
        // Prefer server_id when available
        final serverId = store['server_id'] as int?;
        final body = jsonEncode({
          'name': store['name'],
          'location': store['location'],
          'is_active': store['is_active'] == 1
        });
        if (serverId == null) {
          // If we don't have server id, attempt create instead
          final res = await httpClient.post(
              Uri.parse(api.baseUrl + '/api/stores'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json'
              },
              body: body);
          if (res.statusCode >= 200 && res.statusCode < 300) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final assigned = data['id'] as int?;
            final now = DateTime.now().millisecondsSinceEpoch;
            await dbClient.transaction((txn) async {
              await txn.update('stores',
                  {'server_id': assigned, 'is_synced': 1, 'last_updated': now},
                  where: 'id = ?', whereArgs: [rowId]);
              await txn.update('sync_queue', {'status': 'synced'},
                  where: 'id = ?', whereArgs: [queueId]);
            });
          } else {
            await db.logSyncError(
                queueId: queueId,
                tableName: 'stores',
                rowId: rowId,
                error: 'Create fallback failed: ${res.body}');
            await db.incrementRetry(queueId);
          }
        } else {
          final res = await httpClient.put(
              Uri.parse(api.baseUrl + '/api/stores/$serverId'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json'
              },
              body: body);
          if (res.statusCode >= 200 && res.statusCode < 300) {
            final now = DateTime.now().millisecondsSinceEpoch;
            await dbClient.transaction((txn) async {
              await txn.update('stores', {'is_synced': 1, 'last_updated': now},
                  where: 'id = ?', whereArgs: [rowId]);
              await txn.update('sync_queue', {'status': 'synced'},
                  where: 'id = ?', whereArgs: [queueId]);
            });
          } else if (res.statusCode == 409) {
            await db.logSyncError(
                queueId: queueId,
                tableName: 'stores',
                rowId: rowId,
                error: 'Conflict: ${res.body}');
            await db.incrementRetry(queueId);
          } else {
            await db.logSyncError(
                queueId: queueId,
                tableName: 'stores',
                rowId: rowId,
                error: 'HTTP ${res.statusCode}: ${res.body}');
            await db.incrementRetry(queueId);
          }
        }
      } else if (action == 'DELETE') {
        final serverId = store['server_id'] as int?;
        if (serverId == null) {
          // If server id unknown, just delete the local store and mark queue as synced
          final now = DateTime.now().millisecondsSinceEpoch;
          await dbClient.transaction((txn) async {
            await txn.delete('stores', where: 'id = ?', whereArgs: [rowId]);
            await txn.update('sync_queue', {'status': 'synced'},
                where: 'id = ?', whereArgs: [queueId]);
          });
        } else {
          // Use hard delete endpoint for stores
          final res = await httpClient.delete(
              Uri.parse(api.baseUrl + '/api/stores/$serverId/hard'),
              headers: {'Authorization': 'Bearer $token'});
          if (res.statusCode >= 200 && res.statusCode < 300) {
            final now = DateTime.now().millisecondsSinceEpoch;
            await dbClient.transaction((txn) async {
              await txn.delete('stores', where: 'id = ?', whereArgs: [rowId]);
              await txn.update('sync_queue', {'status': 'synced'},
                  where: 'id = ?', whereArgs: [queueId]);
            });
          } else {
            await db.logSyncError(
                queueId: queueId,
                tableName: 'stores',
                rowId: rowId,
                error: 'HTTP ${res.statusCode}: ${res.body}');
            await db.incrementRetry(queueId);
          }
        }
      }
    } catch (e, st) {
      await db.logSyncError(
          queueId: queueId,
          tableName: 'stores',
          rowId: rowId,
          error: e.toString());
      await db.incrementRetry(queueId);
    }
  }

  Future<void> _syncTransaction(int queueId, int rowId, String action,
      Map<String, dynamic> payload, String token) async {
    final dbClient = await db.database;
    final rows = await dbClient
        .query('transactions', where: 'id = ?', whereArgs: [rowId]);
    if (rows.isEmpty) {
      await db.logSyncError(
          queueId: queueId,
          tableName: 'transactions',
          rowId: rowId,
          error: 'Transaction not found');
      await db.incrementRetry(queueId);
      return;
    }

    final tx = rows.first;
    try {
      if (action == 'CREATE') {
        final itemRows = await dbClient.query('transaction_items',
            where: 'transaction_id = ?', whereArgs: [rowId]);

        // Build items array, mapping local product_ids to server_ids
        final items = <Map<String, dynamic>>[];
        for (final r in itemRows) {
          final localProductId = r['product_id'] as int;

          // Look up the product's server_id
          final prodRows = await dbClient
              .query('products', where: 'id = ?', whereArgs: [localProductId]);

          if (prodRows.isEmpty) {
            debugPrint(
                '_syncTransaction: Product $localProductId not found, skipping transaction');
            await db.logSyncError(
                queueId: queueId,
                tableName: 'transactions',
                rowId: rowId,
                error:
                    'Transaction references non-existent product $localProductId');
            await db.incrementRetry(queueId);
            return;
          }

          final prod = prodRows.first;
          final serverId = prod['server_id'] as int?;

          if (serverId == null) {
            // Product hasn't been synced yet - defer this transaction
            debugPrint(
                '_syncTransaction: Product $localProductId has no server_id, deferring transaction');
            await db.logSyncError(
                queueId: queueId,
                tableName: 'transactions',
                rowId: rowId,
                error:
                    'Transaction references unsynced product $localProductId');
            await db.incrementRetry(queueId);
            return;
          }

          items.add({
            'product_id': serverId, // Use SERVER id, not local id
            'quantity': r['quantity'],
            'price': r['price']
          });
        }

        final body = jsonEncode({
          'transaction_number': tx['transaction_number'],
          'total_amount': tx['total_amount'],
          'payment_method': tx['payment_method'],
          'store_id': tx['store_id'],
          'user_id': tx['user_id'],
          'items': items
        });
        final res = await httpClient.post(
            Uri.parse(api.baseUrl + '/api/transactions'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: body);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final serverId = data['id'] as int?;
          final now = DateTime.now().millisecondsSinceEpoch;
          await dbClient.transaction((txn) async {
            await txn.update(
                'transactions', {'server_id': serverId, 'is_synced': 1},
                where: 'id = ?', whereArgs: [rowId]);
            await txn.update('sync_queue', {'status': 'synced'},
                where: 'id = ?', whereArgs: [queueId]);
          });
        } else {
          await db.logSyncError(
              queueId: queueId,
              tableName: 'transactions',
              rowId: rowId,
              error: 'HTTP ${res.statusCode}: ${res.body}');
          await db.incrementRetry(queueId);
        }
      } else {
        // Other actions could be implemented similarly
        await db.logSyncError(
            queueId: queueId,
            tableName: 'transactions',
            rowId: rowId,
            error: 'Unsupported action: $action');
        await db.incrementRetry(queueId);
      }
    } catch (e) {
      await db.logSyncError(
          queueId: queueId,
          tableName: 'transactions',
          rowId: rowId,
          error: e.toString());
      await db.incrementRetry(queueId);
    }
  }

  Future<void> _syncUser(int queueId, int rowId, String action,
      Map<String, dynamic> payload, String token) async {
    // Minimal implementation: treat user creates/updates as simple POST/PUT
    final dbClient = await db.database;
    final rows =
        await dbClient.query('users', where: 'id = ?', whereArgs: [rowId]);
    if (rows.isEmpty) {
      await db.logSyncError(
          queueId: queueId,
          tableName: 'users',
          rowId: rowId,
          error: 'User missing');
      await db.incrementRetry(queueId);
      return;
    }

    final user = rows.first;
    try {
      if (action == 'CREATE') {
        final body = jsonEncode({'name': user['name'], 'email': user['email']});
        final res = await httpClient.post(Uri.parse(api.baseUrl + '/api/users'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: body);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final serverId = data['id'] as int?;
          final now = DateTime.now().millisecondsSinceEpoch;
          await dbClient.transaction((txn) async {
            await txn.update(
                'users', {'server_id': serverId, 'last_synced': now},
                where: 'id = ?', whereArgs: [rowId]);
            await txn.update('sync_queue', {'status': 'synced'},
                where: 'id = ?', whereArgs: [queueId]);
          });
        } else {
          await db.logSyncError(
              queueId: queueId,
              tableName: 'users',
              rowId: rowId,
              error: 'HTTP ${res.statusCode}: ${res.body}');
          await db.incrementRetry(queueId);
        }
      } else if (action == 'UPDATE') {
        final serverId = user['server_id'] as int?;
        if (serverId == null) {
          await db.logSyncError(
              queueId: queueId,
              tableName: 'users',
              rowId: rowId,
              error: 'Missing server_id for update');
          await db.incrementRetry(queueId);
          return;
        }
        final body = jsonEncode({'name': user['name'], 'email': user['email']});
        final res = await httpClient.put(
            Uri.parse(api.baseUrl + '/api/users/$serverId'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: body);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final now = DateTime.now().millisecondsSinceEpoch;
          await dbClient.transaction((txn) async {
            await txn.update('users', {'last_synced': now},
                where: 'id = ?', whereArgs: [rowId]);
            await txn.update('sync_queue', {'status': 'synced'},
                where: 'id = ?', whereArgs: [queueId]);
          });
        } else {
          await db.logSyncError(
              queueId: queueId,
              tableName: 'users',
              rowId: rowId,
              error: 'HTTP ${res.statusCode}: ${res.body}');
          await db.incrementRetry(queueId);
        }
      } else {
        await db.logSyncError(
            queueId: queueId,
            tableName: 'users',
            rowId: rowId,
            error: 'Unsupported action: $action');
        await db.incrementRetry(queueId);
      }
    } catch (e) {
      await db.logSyncError(
          queueId: queueId,
          tableName: 'users',
          rowId: rowId,
          error: e.toString());
      await db.incrementRetry(queueId);
    }
  }

  Future<void> _syncAnalyticsEvent(int queueId, int rowId, String action,
      Map<String, dynamic> payload, String token) async {
    // Fetch local analytics event
    final dbClient = await db.database;
    final rows = await dbClient
        .query('analytics_events', where: 'id = ?', whereArgs: [rowId]);
    if (rows.isEmpty) {
      await db.logSyncError(
          queueId: queueId,
          tableName: 'analytics_events',
          rowId: rowId,
          error: 'Analytics event not found');
      await db.incrementRetry(queueId);
      return;
    }

    final event = rows.first;
    try {
      if (action == 'CREATE') {
        final metadata = event['metadata_json'] != null
            ? jsonDecode(event['metadata_json'] as String)
            : null;
        final Map<String, dynamic> body = {
          'event_name': event['event_name'] as String?,
          'user_id': event['user_id'] as int?,
          'from_store_id': event['from_store_id'] as int?,
          'to_store_id': event['to_store_id'] as int?,
          'duration_ms': event['duration_ms'] as int?,
          'metadata': metadata,
          'ip_address': event['ip_address'] as String?,
          'user_agent': event['user_agent'] as String?,
        };
        final res = await httpClient.post(
            Uri.parse(api.baseUrl + '/api/analytics/events'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode(body));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final serverId = data['id'] as int?;
          final now = DateTime.now().millisecondsSinceEpoch;
          await dbClient.transaction((txn) async {
            await txn.update(
                'analytics_events', {'server_id': serverId, 'is_synced': 1},
                where: 'id = ?', whereArgs: [rowId]);
            await txn.update('sync_queue', {'status': 'synced'},
                where: 'id = ?', whereArgs: [queueId]);
          });
        } else {
          await db.logSyncError(
              queueId: queueId,
              tableName: 'analytics_events',
              rowId: rowId,
              error: 'HTTP ${res.statusCode}: ${res.body}');
          await db.incrementRetry(queueId);
        }
      } else {
        // Analytics events are typically not updated or deleted
        await db.logSyncError(
            queueId: queueId,
            tableName: 'analytics_events',
            rowId: rowId,
            error: 'Unsupported action: $action');
        await db.incrementRetry(queueId);
      }
    } catch (e) {
      await db.logSyncError(
          queueId: queueId,
          tableName: 'analytics_events',
          rowId: rowId,
          error: e.toString());
      await db.incrementRetry(queueId);
    }
  }

  Future<void> _syncSetting(int queueId, int rowId, String action,
      Map<String, dynamic> payload, String token) async {
    // Fetch local setting
    final dbClient = await db.database;
    final rows =
        await dbClient.query('settings', where: 'id = ?', whereArgs: [rowId]);
    if (rows.isEmpty) {
      await db.logSyncError(
          queueId: queueId,
          tableName: 'settings',
          rowId: rowId,
          error: 'Setting not found');
      await db.incrementRetry(queueId);
      return;
    }

    final setting = rows.first;
    try {
      final settingType = setting['setting_type'] as String;
      final key = setting['key'] as String;
      final value = setting['value'] as String;
      final userId = setting['user_id'] as int?;
      final storeId = setting['store_id'] as int?;

      if (action == 'CREATE' || action == 'UPDATE') {
        // Determine the correct endpoint based on setting type
        String endpoint;
        Map<String, dynamic> body;

        if (settingType == 'store') {
          endpoint = '/api/settings/store';
          body = {key: value};
        } else if (settingType == 'user') {
          endpoint = '/api/settings/user';
          body = {key: value};
        } else if (settingType == 'system') {
          endpoint = '/api/settings/system';
          body = {'key': key, 'value': value};
        } else {
          await db.logSyncError(
              queueId: queueId,
              tableName: 'settings',
              rowId: rowId,
              error: 'Unknown setting type: $settingType');
          await db.incrementRetry(queueId);
          return;
        }

        // Settings endpoints only support PUT (they do upsert internally)
        final uri = Uri.parse(api.baseUrl + endpoint);
        final res = await httpClient.put(uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode(body));

        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final serverId = data['id'] as int?;
          final now = DateTime.now().millisecondsSinceEpoch;
          await dbClient.transaction((txn) async {
            await txn.update('settings',
                {'server_id': serverId, 'is_synced': 1, 'updated_at': now},
                where: 'id = ?', whereArgs: [rowId]);
            await txn.update('sync_queue', {'status': 'synced'},
                where: 'id = ?', whereArgs: [queueId]);
          });
        } else {
          await db.logSyncError(
              queueId: queueId,
              tableName: 'settings',
              rowId: rowId,
              error: 'HTTP ${res.statusCode}: ${res.body}');
          await db.incrementRetry(queueId);
        }
      } else {
        await db.logSyncError(
            queueId: queueId,
            tableName: 'settings',
            rowId: rowId,
            error: 'Unsupported action: $action');
        await db.incrementRetry(queueId);
      }
    } catch (e) {
      await db.logSyncError(
          queueId: queueId,
          tableName: 'settings',
          rowId: rowId,
          error: e.toString());
      await db.incrementRetry(queueId);
    }
  }
}
