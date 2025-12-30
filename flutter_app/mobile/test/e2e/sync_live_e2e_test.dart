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
  final base = Platform.environment['SYNC_LIVE_BASE_URL'];
  final user = Platform.environment['SYNC_LIVE_USER'];
  final pass = Platform.environment['SYNC_LIVE_PASS'];
  final tokenEnv = Platform.environment['SYNC_LIVE_TOKEN'];

  final skipMsg =
      base == null ? 'Set SYNC_LIVE_BASE_URL to run live sync tests' : null;

  test('live sync push/pull against running backend', () async {
    if (base == null) {
      return; // skipped by environment
    }

    // Setup DB and SyncService
    databaseFactory = databaseFactoryFfi;
    final tmpDir = await Directory.systemTemp.createTemp('pos_live_sync_');
    final dbPath = p.join(tmpDir.path, 'e2e_live.sqlite');
    final db = await AppDatabase.openWithPath(dbPath);

    // Determine token
    String? token = tokenEnv;
    if (token == null && user != null && pass != null) {
      final res = await http.post(Uri.parse('$base/auth/token'),
          body: {'username': user, 'password': pass});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        token = data['access_token'] as String?;
      } else {
        throw Exception(
            'Failed to get token from live server: ${res.statusCode} ${res.body}');
      }
    }

    if (token == null) {
      throw Exception(
          'No token available for live sync test; set SYNC_LIVE_TOKEN or SYNC_LIVE_USER & SYNC_LIVE_PASS');
    }

    SharedPreferences.setMockInitialValues({'access_token': token});

    final syncService =
        SyncService(db, httpClient: http.Client(), serverBase: base);

    // Enqueue a product
    final tempId = await syncService.enqueueCreateProduct(
        name: 'LIVE E2E Prod', description: 'live', price: 1.23, stock: 2);

    final pending = await db.getPendingChanges();
    expect(pending.length, greaterThan(0));

    final res = await syncService.pushChanges(jwtToken: token);
    expect(res['id_map'], isNotEmpty);

    final after = await db.getPendingChanges();
    expect(after, isEmpty);

    final pulled = await syncService.pullChanges(
        since: DateTime.fromMillisecondsSinceEpoch(0));
    expect(pulled, isNotNull);

    await db.close();
    try {
      final tmp = Directory(tmpDir.path);
      if (await tmp.exists()) await tmp.delete(recursive: true);
    } catch (_) {}
  }, skip: skipMsg != null, timeout: const Timeout(Duration(minutes: 3)));
}
