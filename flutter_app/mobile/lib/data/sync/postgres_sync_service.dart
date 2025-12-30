import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
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

  PostgresSyncService({
    required this.db,
    required this.api,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
    Connectivity? connectivity,
  })  : secureStorage = secureStorage ?? const FlutterSecureStorage(),
        httpClient = httpClient ?? http.Client(),
        connectivity = connectivity ?? Connectivity();

  Future<bool> syncPendingChanges() async {
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
          case 'transactions':
            await _syncTransaction(queueId, rowId, action, payload, token);
            break;
          case 'users':
            await _syncUser(queueId, rowId, action, payload, token);
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
  }

  /// Batch variant that aggregates pending queue items into a single /api/sync/push
  /// request and applies server responses (id_map, conflicts, applied) atomically.
  Future<bool> syncPendingChangesBatch({int limit = 100}) async {
    // Check connectivity
    final conn = await connectivity.checkConnectivity();
    if (conn == ConnectivityResult.none) return false;

    // Check token
    final token = await secureStorage.read(key: 'access_token');
    if (token == null) return false;

    final items = await db.getPendingSyncItems(limit: limit);
    if (items.isEmpty) return true;

    // Build change set
    final List<Map<String, dynamic>> changes = [];
    final Map<String, int> tempMap = {}; // temp_id -> rowId
    final Map<String, int> queueByTemp = {}; // temp_id -> queueId

    for (final item in items) {
      final queueId = item['id'] as int;
      final tableName = item['table_name'] as String;
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
                  ? DateTime.fromMillisecondsSinceEpoch(local['last_updated'])
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
        default:
          // Log unknown and increment retry
          await db.logSyncError(
              queueId: queueId,
              tableName: tableName,
              rowId: rowId,
              error: 'Unknown table in batch');
          await db.incrementRetry(queueId);
      }
    }

    if (changes.isEmpty) return true;

    try {
      final res = await api.pushChangesBatch(changes, token: token);
      final idMap = (res['id_map'] as Map?)?.cast<String, dynamic>() ?? {};
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
            await txn.update('products',
                {'server_id': serverId, 'is_synced': 1, 'last_updated': now},
                where: 'id = ?', whereArgs: [rowId]);
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
              final rows = await txn
                  .query('products', where: 'server_id = ?', whereArgs: [id]);
              for (final r in rows) {
                final rowId = r['id'] as int;
                await txn
                    .delete('products', where: 'id = ?', whereArgs: [rowId]);
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
              final matched = await txn
                  .query('products', where: 'server_id = ?', whereArgs: [id]);
              for (final m in matched) {
                await txn.update('sync_queue', {'status': 'synced'},
                    where: 'row_id = ?', whereArgs: [m['id']]);
              }
            }
          }
        }

        // Record conflicts
        for (final c in conflicts) {
          final table = c['resource_type'] ?? 'unknown';
          final id = c['id'] ?? -1;
          final message = c['message'] ?? c.toString();
          // Find queue items that match the conflict (best-effort) and increment retry + log
          final qrows = await txn
              .query('sync_queue', where: 'status = ?', whereArgs: ['pending']);
          for (final qr in qrows) {
            await txn.insert('sync_errors', {
              'queue_id': qr['id'],
              'table_name': table,
              'row_id': qr['row_id'],
              'error': message,
              'created_at': DateTime.now().millisecondsSinceEpoch
            });
            await txn.rawUpdate(
                'UPDATE sync_queue SET retry_count = retry_count + 1 WHERE id = ?',
                [qr['id']]);
            final row = (await txn.query('sync_queue',
                    where: 'id = ?', whereArgs: [qr['id']]))
                .first;
            if ((row['retry_count'] as int) >= 5) {
              await txn.update('sync_queue', {'status': 'failed'},
                  where: 'id = ?', whereArgs: [qr['id']]);
            }
          }
        }
      });

      return true;
    } catch (e) {
      // On HTTP or parse exceptions, increment retry for all queued items
      for (final item in items) {
        await db.incrementRetry(item['id'] as int);
      }
      return true; // non-fatal
    }
  }

  /// Pull changes from the server since the given timestamp and apply to local DB.
  /// This mirrors the behaviour expected by syncUsing and is non-fatal.
  Future<void> pullChangesSinceSeq() async {
    final token = await secureStorage.read(key: 'access_token');
    if (token == null) return;

    final lastSeq = await db.getLastServerSeq();
    final res = await api.fetchChangesSinceSeq(lastSeq, token: token);
    final changes =
        (res['changes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final headSeq = res['head_seq'] as int? ?? lastSeq;

    if (changes.isEmpty) {
      await db.setLastServerSeq(headSeq);
      return;
    }

    final dbClient = await db.database;
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
                await txn
                    .delete('products', where: 'id = ?', whereArgs: [r['id']]);
              }
            }
          }
        }
        // TODO: handle other entity types (stores, users, etc.) as needed
      }

      // Commit head seq (atomic with changes applied)
      await txn.insert(
          'sync_meta', {'key': 'last_server_seq', 'value': headSeq.toString()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
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
        final items = itemRows
            .map((r) => {
                  'product_id': r['product_id'],
                  'quantity': r['quantity'],
                  'price': r['price']
                })
            .toList();
        final body = jsonEncode({
          'transaction_number': tx['transaction_number'],
          'total_amount': tx['total_amount'],
          'payment_method': tx['payment_method'],
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
}
