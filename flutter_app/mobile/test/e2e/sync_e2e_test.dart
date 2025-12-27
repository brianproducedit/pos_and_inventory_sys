import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/sync/sync_service.dart';
import 'package:mobile/db/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sync e2e', () {
    late HttpServer server;
    late String baseUrl;
    late AppDatabase db;
    late SyncService syncService;

    // Server state shared with individual tests
    Map<int, Map<String, dynamic>> products = {};
    int nextId = 1;

    setUp(() async {
      // Allow real HTTP in this test (some unit tests set HttpOverrides)
      final originalOverrides = HttpOverrides.current;
      HttpOverrides.global = null;

      // start local server
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      baseUrl = 'http://localhost:$port';

      // Reset server state
      products = {};
      nextId = 1;

      // Server request handler
      server.listen((HttpRequest req) async {
        final path = req.uri.path;
        if (req.method == 'POST' && path == '/api/sync/push') {
          final body = await utf8.decoder.bind(req).join();
          final data = jsonDecode(body) as Map<String, dynamic>;
          final changes =
              (data['changes'] as List).cast<Map<String, dynamic>>();

          final List<Map<String, dynamic>> applied = [];
          final Map<String, int> idMap = {};

          for (final ch in changes) {
            final op = ch['operation'];
            if (op == 'create') {
              final tempId = ch['temp_id'] as String?;
              final cdata = ch['data'] as Map<String, dynamic>;
              final serverId = nextId++;
              products[serverId] = {
                'id': serverId,
                'name': cdata['name'],
                'description': cdata['description'],
                'price': cdata['price'],
                'stock_quantity': cdata['stock_quantity'],
                'store_id': cdata['store_id'],
                'updated_at': DateTime.now().toIso8601String(),
              };
              applied.add({'operation': 'create', 'id': serverId});
              if (tempId != null) idMap[tempId] = serverId;
            } else if (op == 'update') {
              final id = ch['id'] as int?;
              final cdata = ch['data'] as Map<String, dynamic>? ?? {};
              final lastUpdated = ch['last_updated'] as String?;
              if (id == null || !products.containsKey(id)) {
                // Not found
                // treat as conflict for simplicity
                applied.add({'operation': 'update', 'id': id});
              } else {
                final serverRec = products[id]!;
                final serverUpdated = serverRec['updated_at'] != null
                    ? DateTime.parse(serverRec['updated_at'])
                    : DateTime.now();
                final clientUpdated = lastUpdated != null
                    ? DateTime.parse(lastUpdated)
                    : DateTime.fromMillisecondsSinceEpoch(0);
                if (clientUpdated.isBefore(serverUpdated)) {
                  // conflict
                  final conflict = {
                    'resource_type': 'product',
                    'id': id,
                    'message': 'Conflict: server has newer record',
                    'server_data': serverRec,
                    'suggestion': 'fetch_or_force'
                  };
                  // append to conflicts list
                  // conflicts will be returned below
                  applied.add({'conflict_marker': true});
                  // store conflict in a temporary place
                  // we'll build conflicts from applied markers
                  idMap['__last_conflict'] = id;
                } else {
                  // apply update
                  serverRec['price'] = cdata['price'] ?? serverRec['price'];
                  serverRec['updated_at'] = DateTime.now().toIso8601String();
                  applied.add({'operation': 'update', 'id': id});
                }
              }
            }
          }

          // Build conflicts list if any conflict markers were added
          final List<Map<String, dynamic>> conflictsList = [];
          if (idMap.containsKey('__last_conflict')) {
            final cid = idMap.remove('__last_conflict') as int;
            final serverRec = products[cid];
            conflictsList.add({
              'resource_type': 'product',
              'id': cid,
              'message': 'Conflict: server has newer record',
              'server_data': serverRec,
              'suggestion': 'fetch_or_force'
            });
          }

          final resp = jsonEncode({
            'applied': applied,
            'id_map': idMap,
            'conflicts': conflictsList
          });
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(resp);
          await req.response.close();
          return;
        }

        if (req.method == 'GET' && path == '/api/sync/changes') {
          // Return all products as changes
          final changeList = products.values
              .map((p) => {
                    'data': {
                      'name': p['name'],
                      'description': p['description'],
                      'price': p['price'],
                      'stock_quantity': p['stock_quantity'],
                      'store_id': p['store_id']
                    }
                  })
              .toList();
          final resp = jsonEncode({
            'changes': {
              'products': changeList,
            }
          });
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(resp);
          await req.response.close();
          return;
        }

        // Not found
        req.response.statusCode = 404;
        await req.response.close();
      });

      // Create a temp DB file
      // Ensure sqflite ffi factory is registered for desktop tests
      databaseFactory = databaseFactoryFfi;

      final tmpDir = await Directory.systemTemp.createTemp('pos_e2e_');
      final dbPath = p.join(tmpDir.path, 'e2e.sqlite');
      db = await AppDatabase.openWithPath(dbPath);

      // Initialize shared preferences mock for the test
      SharedPreferences.setMockInitialValues({});

      // Create sync service pointed to our local server
      syncService =
          SyncService(db, httpClient: http.Client(), serverBase: baseUrl);

      // restore overrides at teardown; keep a copy in the scope
      addTearDown(() async {
        await server.close(force: true);
        await db.close();
        try {
          // cleanup temp dir
          final tmp = Directory(tmpDir.path);
          if (await tmp.exists()) await tmp.delete(recursive: true);
        } catch (_) {}
        HttpOverrides.global = originalOverrides;
      });
    });

    test('push and pull flow end-to-end', () async {
      // Enqueue a local create
      final tempId = await syncService.enqueueCreateProduct(
          name: 'E2E Product', description: 'desc', price: 12.5, stock: 3);

      // Ensure pending changes exist
      final pending = await db.getPendingChanges();
      expect(pending.length, greaterThan(0));

      // Push changes to the local server
      final res = await syncService.pushChanges();
      expect(res['id_map'], isNotEmpty);

      // After push, pending queue should be cleared
      final after = await db.getPendingChanges();
      expect(after, isEmpty);

      // Now simulate server-side product added earlier is visible via pull
      final changes = await syncService.pullChanges(
          since: DateTime.now().subtract(Duration(days: 1)));
      expect(changes, isNotNull);
      final allProds = await db.getAllProducts();
      expect(allProds.length, greaterThanOrEqualTo(1));

      // SharedPreferences last_sync_time should be set
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_sync_time'), isNotNull);
    });

    test('push should return conflict when server has newer record', () async {
      // Create a product on the server state
      final serverId = nextId++;
      products[serverId] = {
        'id': serverId,
        'name': 'Conflicted Product',
        'description': 'server desc',
        'price': 99.0,
        'stock_quantity': 1,
        'store_id': 1,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Insert a queued update with an older last_updated timestamp
      final olderTime =
          DateTime.now().subtract(Duration(days: 1)).toIso8601String();
      final payload = {
        'resource_type': 'product',
        'operation': 'update',
        'id': serverId,
        'data': {'price': 10.0},
        'last_updated': olderTime,
      };

      await db.enqueueChange(
          clientTempId: null,
          resourceType: 'product',
          operation: 'update',
          payloadJson: jsonEncode(payload));

      final res = await syncService.pushChanges();
      expect((res['conflicts'] as List).isNotEmpty, isTrue);
    });
  });
}
