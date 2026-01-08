import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart';
import '../db/app_database.dart';

// Default server base: prefer configured environment constant (suitable for physical devices)
import '../config/env.dart';

const String defaultServerBase = Env.baseUrl;

class SyncService {
  final dynamic db;
  final http.Client httpClient;
  final String
  serverBase; // instance-level server base so tests can override it
  static const Uuid _uuid = Uuid();

  SyncService(this.db, {http.Client? httpClient, String? serverBase})
    : httpClient = httpClient ?? http.Client(),
      serverBase = serverBase ?? defaultServerBase;

  Future<String> enqueueCreateProduct({
    required String name,
    String? description,
    double price = 0.0,
    int stock = 0,
    int? storeId,
  }) async {
    // If caller didn't provide a storeId, try to read user's current store from prefs
    if (storeId == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        storeId = prefs.getInt('current_store_id');
      } catch (_) {
        storeId = null;
      }
    }

    // If still null, creating a product without a store is invalid in the server schema.
    if (storeId == null) {
      throw Exception(
        'No active store selected. Please select a store before creating products.',
      );
    }

    final clientId = _uuid.v4();
    final entry = ProductsCompanion.insert(
      clientId: Value(clientId),
      name: name,
      description: Value(description),
      price: Value(price),
      stockQuantity: Value(stock),
      storeId: storeId,
    );
    await db.insertProduct(entry);

    final payload = {
      'resource_type': 'product',
      'operation': 'create',
      'temp_id': clientId,
      'data': {
        'name': name,
        'description': description,
        'price': price,
        'stock_quantity': stock,
        'store_id': storeId,
      },
    };

    await db.enqueueChange(
      clientTempId: clientId,
      resourceType: 'product',
      operation: 'create',
      payloadJson: jsonEncode(payload),
    );
    return clientId;
  }

  Future<Map<String, dynamic>> pushChanges({String? jwtToken}) async {
    final items = await db.getPendingChanges();
    if (items.isEmpty) return {'applied': [], 'conflicts': []};

    final changes = items.map((it) => jsonDecode(it.payloadJson)).toList();

    // Validate pending changes against server required fields to avoid server 500s
    // e.g., product creates require a store_id which must not be null
    final invalidTempIds = <String>[];
    for (final ch in changes) {
      try {
        if ((ch['resource_type'] == 'product') &&
            (ch['operation'] == 'create')) {
          final data = ch['data'] as Map<String, dynamic>? ?? {};
          if (data['store_id'] == null) {
            final tempId = ch['temp_id'] as String? ?? '';
            invalidTempIds.add(tempId);
          }
        }
      } catch (_) {
        // ignore malformed payloads here — they'll be handled by server if necessary
      }
    }
    if (invalidTempIds.isNotEmpty) {
      throw Exception(
        'Pending product create(s) missing store_id (temp_ids: ${invalidTempIds.join(', ')}). Select a store or remove the pending changes before syncing.',
      );
    }

    final body = jsonEncode({
      'client_id': 'flutter-device',
      'changes': changes,
    });

    final headers = {'Content-Type': 'application/json'};
    // If caller didn't provide a token, try to fetch the stored access_token
    if (jwtToken == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        jwtToken = prefs.getString('access_token');
      } catch (_) {
        jwtToken = null;
      }
    }
    if (jwtToken != null) headers['Authorization'] = 'Bearer $jwtToken';

    final res = await httpClient.post(
      Uri.parse('$serverBase/api/sync/push'),
      headers: headers,
      body: body,
    );
    if (res.statusCode != 200) {
      throw Exception('Sync push failed: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body);

    // Apply id mapping: map temp ids to server ids
    final idMap = data['id_map'] as Map<String, dynamic>? ?? {};
    for (final entry in idMap.entries) {
      final tempId = entry.key;
      final serverId = entry.value as int;
      await db.updateProductServerId(tempId, serverId);
    }

    // Remove applied items from queue
    final applied = data['applied'] as List<dynamic>? ?? [];
    for (final a in applied) {
      // find matching queue item by temp id (for create) or resource+id for updates
      if (a['operation'] == 'create' && a.containsKey('id')) {
        final serverId = a['id'];
        final tempId = idMap.entries
            .firstWhere(
              (e) => e.value == serverId,
              orElse: () => const MapEntry('', null),
            )
            .key;
        if (tempId != '') {
          // Snapshot pending changes to avoid concurrent modification during deletions
          final qItems = List.of(await db.getPendingChanges());
          for (final q in qItems) {
            try {
              final p = jsonDecode(q.payloadJson);
              if (p['temp_id'] == tempId) {
                await db.deleteQueueItem(q.id);
              }
            } catch (_) {}
          }
        }
      }
    }

    // Persist conflicts for UI resolution and return them to caller
    final conflicts = data['conflicts'] ?? [];
    try {
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('last_sync_conflicts', jsonEncode(conflicts));
      await prefs.setInt('sync_conflict_count', (conflicts as List).length);
    } catch (_) {}

    // For simplicity, if there are conflicts, return them to UI for manual handling
    return {
      'applied': data['applied'] ?? [],
      'conflicts': conflicts,
      'id_map': idMap,
    };
  }

  /// Attach a store_id to pending product create queue items.
  /// If [tempIds] provided, only updates those temp ids; otherwise updates all product creates.
  Future<int> attachStoreToPendingCreates({
    required int storeId,
    List<String>? tempIds,
  }) async {
    final items = await db.getPendingChanges();
    var updated = 0;
    for (final q in items) {
      try {
        final p = jsonDecode(q.payloadJson) as Map<String, dynamic>;
        if (p['resource_type'] == 'product' && p['operation'] == 'create') {
          final tempId = p['temp_id'] as String?;
          if (tempIds == null || (tempId != null && tempIds.contains(tempId))) {
            final data = p['data'] as Map<String, dynamic>? ?? {};
            data['store_id'] = storeId;
            p['data'] = data;
            await db.updateQueuePayload(q.id, jsonEncode(p));
            updated++;
          }
        }
      } catch (_) {}
    }
    return updated;
  }

  /// Force-update a single resource on the server as superadmin (adds `_force: true`)
  Future<Map<String, dynamic>> forceUpdate({
    required String resourceType,
    required int id,
    required Map<String, dynamic> data,
    String? jwtToken,
  }) async {
    final change = {
      'resource_type': resourceType,
      'operation': 'update',
      'id': id,
      'data': {...data, '_force': true},
      'last_updated': DateTime.now().toIso8601String(),
    };

    final body = jsonEncode({
      'client_id': 'flutter-device',
      'changes': [change],
    });
    final headers = {'Content-Type': 'application/json'};
    if (jwtToken != null) headers['Authorization'] = 'Bearer $jwtToken';

    final res = await httpClient.post(
      Uri.parse('$serverBase/api/sync/push'),
      headers: headers,
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception(
        'Sync force update failed: ${res.statusCode} ${res.body}',
      );
    }

    final dataResp = jsonDecode(res.body);
    return {
      'applied': dataResp['applied'] ?? [],
      'conflicts': dataResp['conflicts'] ?? [],
      'id_map': dataResp['id_map'] ?? {},
    };
  }

  Future<List<Map<String, dynamic>>> pullChanges({
    required DateTime since,
    String types = 'products',
    String? jwtToken,
  }) async {
    final sinceIso = since.toIso8601String();
    final uri = Uri.parse(
      '$serverBase/api/sync/changes?since=$sinceIso&types=$types',
    );
    final headers = <String, String>{};
    if (jwtToken == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        jwtToken = prefs.getString('access_token');
      } catch (_) {
        jwtToken = null;
      }
    }
    if (jwtToken != null) headers['Authorization'] = 'Bearer $jwtToken';
    final res = await httpClient.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw Exception('Sync pull failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body);
    final changes = data['changes'] as Map<String, dynamic>;

    final prods = (changes['products'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    for (final p in prods) {
      final d = p['data'] as Map<String, dynamic>;
      final storeId = d['store_id'] as int?;

      // Skip products without a store_id (invalid data from server)
      if (storeId == null) continue;

      // Simplified upsert: insert server-authoritative product into local DB.
      // NOTE: For production, add a dedicated server_id column and proper conflict
      // resolution / deduplication instead of blind inserts.
      final entry = ProductsCompanion.insert(
        clientId: const Value.absent(),
        name: d['name'] as String? ?? '',
        description: Value(d['description'] as String?),
        price: Value((d['price'] as num?)?.toDouble() ?? 0.0),
        stockQuantity: Value(d['stock_quantity'] as int? ?? 0),
        storeId: storeId,
      );

      try {
        await db.insertProduct(entry);
      } catch (_) {
        // ignore insert errors for now
      }
    }

    // Save last sync time
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('last_sync_time', DateTime.now().toIso8601String());

    return prods;
  }
}
