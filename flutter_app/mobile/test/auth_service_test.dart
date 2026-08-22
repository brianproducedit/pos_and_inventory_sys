import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'test_utils/fake_http_client.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/db/app_database.dart';
import 'package:drift/drift.dart' hide isNull;

class TestSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    required String key,
    required String? value,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
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
    AppleOptions? iOptions,
    required String key,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async =>
      _store[key];

  @override
  Future<void> delete({
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    required String key,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async =>
      _store.remove(key);
}

late AppDatabase testDb;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    testDb = AppDatabase.inMemory();
  });

  tearDown(() async {
    await testDb.close();
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
    final auth = AuthService(mockClient, fakeStore, testDb);

    final res = await auth.login('u', 'p');
    expect(res['access_token'], 'tok-123');

    final token = await auth.getToken();
    expect(token, 'tok-123');

    final users = await testDb.select(testDb.users).get();
    expect(users.length, 1);
    expect(users.first.serverId, 9);
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
    final auth = AuthService(mockClient, fakeStore, testDb);

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

    // Insert test user using Drift
    await testDb.into(testDb.users).insert(UsersCompanion.insert(
          serverId: const Value(1),
          username: 'testuser',
          passwordHash: 'hash',
          fullName: const Value('Test User'),
          role: UserRole.admin,
          storeId: const Value(1),
        ));

    final auth = AuthService(null, fakeStore, testDb);
    final success = await auth.offlineLogin(testDb);
    expect(success, true);
  });

  test('offlineLogin fails without stored credentials', () async {
    final fakeStore = TestSecureStorage();
    final auth = AuthService(null, fakeStore, testDb);
    final success = await auth.offlineLogin(testDb);
    expect(success, false);
  });
}
