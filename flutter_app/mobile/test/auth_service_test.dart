import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'test_utils/fake_http_client.dart';
import 'test_helpers.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    required String key,
    required String? value,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    required String key,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async =>
      _store[key];

  @override
  Future<void> delete({
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    required String key,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async =>
      _store.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    initSqfliteForTests();
    await DatabaseHelper.initTestDb();
  });

  tearDown(() async {
    await DatabaseHelper.resetTestDb();
  });

  test('login stores token and user in local DB', () async {
    final builder = FakeHttpClient();
    builder.when('/auth/token', (req) async {
      return http.Response(jsonEncode({'access_token': 'tok-123'}), 200);
    });
    builder.when('/api/users/me', (req) async {
      return http.Response(
          jsonEncode({'id': 9, 'name': 'Test', 'email': 't@example.com'}), 200,
          headers: {'content-type': 'application/json'});
    });
    final mockClient = builder.build();

    final fakeStore = TestSecureStorage();
    final auth = AuthService(mockClient, fakeStore, DatabaseHelper());

    final res = await auth.login('u', 'p');
    expect(res['access_token'], 'tok-123');

    final token = await auth.getToken();
    expect(token, 'tok-123');

    final db = await DatabaseHelper().database;
    final rows = await db.query('users');
    expect(rows.length, 1);
    expect(rows.first['server_id'], 9);
    expect(rows.first['email'], 't@example.com');
  });

  test('login rolls back token if fetching user info fails', () async {
    final builder = FakeHttpClient();
    builder.when('/auth/token', (req) async {
      return http.Response(jsonEncode({'access_token': 'tok-456'}), 200);
    });
    builder.when('/api/users/me', (req) async {
      return http.Response('Server error', 500);
    });
    final mockClient = builder.build();

    final fakeStore = TestSecureStorage();
    final auth = AuthService(mockClient, fakeStore, DatabaseHelper());

    // Expect that login fails with a thrown exception due to user info fetch failure
    expect(() async => await auth.login('u', 'p'), throwsA(isA<Exception>()));

    // Token should have been deleted by rollback
    final token = await auth.getToken();
    expect(token, isNull);
  });

  test('offlineLogin succeeds with stored credentials and local user',
      () async {
    final fakeStore = TestSecureStorage();
    await fakeStore.write(key: 'username', value: 'testuser');
    await fakeStore.write(key: 'password', value: 'testpass');

    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;
    await db.insert('users', {
      'server_id': 1,
      'username': 'testuser',
      'name': 'Test User',
      'email': 'test@example.com',
      'role': 'admin',
      'store_id': 1,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'last_synced': DateTime.now().millisecondsSinceEpoch,
    });

    final auth = AuthService(null, fakeStore, dbHelper);
    final success = await auth.offlineLogin(dbHelper);
    expect(success, true);
  });

  test('offlineLogin fails without stored credentials', () async {
    final fakeStore = TestSecureStorage();
    final auth = AuthService(null, fakeStore, DatabaseHelper());
    final success = await auth.offlineLogin(DatabaseHelper());
    expect(success, false);
  });
}

class _BadDbHelper {
  Future<dynamic> get database async {
    return _BadDb();
  }
}

class _BadDb {
  Future<int> insert(String table, Map<String, Object?> values,
      {dynamic conflictAlgorithm}) async {
    throw Exception('DB insert failed');
  }
}
