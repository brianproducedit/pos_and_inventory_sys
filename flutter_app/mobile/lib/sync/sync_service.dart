import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart';
import '../db/app_database.dart';

// Adjust to match your dev server (Android emulator uses 10.0.2.2 to reach host)
const String serverBase =
    String.fromEnvironment('SERVER_BASE', defaultValue: 'http://10.0.2.2:8000');

class SyncService {
  final AppDatabase db;
  static const Uuid _uuid = Uuid();

  SyncService(this.db);

  Future<String> enqueueCreateProduct(
      {required String name,
      String? description,
      double price = 0.0,
      int stock = 0,
      int? storeId}) async {
    final clientId = _uuid.v4();
    final entry = ProductsCompanion.insert(
      clientId: Value(clientId),
      name: name,
      description: Value(description),
      price: Value(price),
      stockQuantity: Value(stock),
      storeId: Value(storeId),
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
        'store_id': storeId
      }
    };

    await db.enqueueChange(
        clientTempId: clientId,
        resourceType: 'product',
        operation: 'create',
        payloadJson: jsonEncode(payload));
    return clientId;
  }

  Future<Map<String, dynamic>> pushChanges({String? jwtToken}) async {
    final items = await db.getPendingChanges();
    if (items.isEmpty) return {'applied': [], 'conflicts': []};

    final changes = items.map((it) => jsonDecode(it.payloadJson)).toList();
    final body =
        jsonEncode({'client_id': 'flutter-device', 'changes': changes});

    final headers = {'Content-Type': 'application/json'};
    if (jwtToken != null) headers['Authorization'] = 'Bearer $jwtToken';

    final res = await http.post(Uri.parse('$serverBase/api/sync/push'),
        headers: headers, body: body);
    if (res.statusCode != 200) {
      throw Exception('Sync push failed: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body);

    // Apply id mapping: map temp ids to server ids
    final idMap = data['id_map'] as Map<String, dynamic>? ?? {};
    for (final entry in idMap.entries) {
      final tempId = entry.key;
      final serverId = entry.value as int;
      // TODO: update local product to reflect server id if needed. For now, clear clientId
      await db.updateProductServerId(tempId, serverId);
    }

    // Remove applied items from queue
    final applied = data['applied'] as List<dynamic>? ?? [];
    for (final a in applied) {
      // find matching queue item by temp id (for create) or resource+id for updates
      if (a['operation'] == 'create' && a.containsKey('id')) {
        final serverId = a['id'];
        final tempId = idMap.entries
            .firstWhere((e) => e.value == serverId,
                orElse: () => MapEntry('', null))
            .key;
        if (tempId != '') {
          final qItems = await db.getPendingChanges();
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

    // For simplicity, if there are conflicts, return them to UI for manual handling
    return {
      'applied': data['applied'] ?? [],
      'conflicts': data['conflicts'] ?? [],
      'id_map': idMap
    };
  }

  Future<List<Map<String, dynamic>>> pullChanges(
      {required DateTime since,
      String types = 'products',
      String? jwtToken}) async {
    final sinceIso = since.toIso8601String();
    final uri =
        Uri.parse('$serverBase/api/sync/changes?since=$sinceIso&types=$types');
    final headers = <String, String>{};
    if (jwtToken != null) headers['Authorization'] = 'Bearer $jwtToken';
    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw Exception('Sync pull failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body);
    final changes = data['changes'] as Map<String, dynamic>;

    final prods = (changes['products'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    for (final p in prods) {
      final d = p['data'] as Map<String, dynamic>;
      // Simplified upsert: insert server-authoritative product into local DB.
      // NOTE: For production, add a dedicated server_id column and proper conflict
      // resolution / deduplication instead of blind inserts.
      final entry = ProductsCompanion.insert(
        clientId: Value(null),
        name: d['name'] as String? ?? '',
        description: Value(d['description'] as String?),
        price: Value((d['price'] as num?)?.toDouble() ?? 0.0),
        stockQuantity: Value(d['stock_quantity'] as int? ?? 0),
        storeId: Value(d['store_id'] as int?),
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
