import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mobile/db/app_database.dart';
import 'package:mobile/services/offline_auth_service.dart';
import 'package:mobile/data/remote/api_client.dart';

/// Test secure storage implementation that stores data in memory
class TestSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  Map<String, String> get store => _store;

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

  @override
  Future<Map<String, String>> readAll({
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async =>
      Map.from(_store);

  @override
  Future<void> deleteAll({
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async =>
      _store.clear();
}

/// Hash password the same way OfflineAuthService does
String hashPassword(String password, String username) {
  final bytes = utf8.encode(password + username.toLowerCase());
  final hash = sha256.convert(bytes);
  return hash.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late TestSecureStorage secureStorage;
  late OfflineAuthService authService;

  setUp(() async {
    // Create fresh in-memory database for each test
    db = AppDatabase.inMemory();
    secureStorage = TestSecureStorage();
    authService = OfflineAuthService(
      db: db,
      apiClient: ApiClient(), // Won't be used in offline tests
      storage: secureStorage,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Offline Login Tests', () {
    test(
        'loginOffline succeeds with correct credentials when user exists locally',
        () async {
      // Arrange: Create a user in local database with hashed password
      const username = 'testuser';
      const password = 'testpass123';
      final passwordHash = hashPassword(password, username);

      await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-123'),
            username: username,
            passwordHash: passwordHash,
            fullName: const Value('Test User'),
            role: UserRole.admin,
            storeId: const Value(1),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Act: Attempt offline login
      final result = await authService.loginOffline(username, password);

      // Assert
      expect(result.success, isTrue);
      expect(result.user, isNotNull);
      expect(result.user!.username, equals(username));
      expect(result.user!.role, equals(UserRole.admin));
      expect(
          result.token, isNotNull); // Local session token should be generated
    });

    test('loginOffline fails with incorrect password', () async {
      // Arrange
      const username = 'testuser';
      const password = 'correctpass';
      final passwordHash = hashPassword(password, username);

      await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-456'),
            username: username,
            passwordHash: passwordHash,
            fullName: const Value('Test User'),
            role: UserRole.cashier,
            storeId: const Value(1),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Act: Attempt login with wrong password
      final result = await authService.loginOffline(username, 'wrongpassword');

      // Assert
      expect(result.success, isFalse);
      expect(result.message, contains('Invalid password'));
      expect(result.user, isNull);
    });

    test('loginOffline fails when user does not exist locally', () async {
      // Act: Attempt login for non-existent user
      final result = await authService.loginOffline('nonexistent', 'password');

      // Assert
      expect(result.success, isFalse);
      expect(result.message, contains('User not found'));
      expect(result.user, isNull);
    });

    test('loginOffline fails when user is inactive', () async {
      // Arrange: Create inactive user
      const username = 'inactiveuser';
      const password = 'testpass';
      final passwordHash = hashPassword(password, username);

      await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-789'),
            username: username,
            passwordHash: passwordHash,
            fullName: const Value('Inactive User'),
            role: UserRole.cashier,
            storeId: const Value(1),
            isActive: const Value(false), // User is deactivated
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Act
      final result = await authService.loginOffline(username, password);

      // Assert
      expect(result.success, isFalse);
      expect(result.message,
          contains('User not found')); // Inactive users are filtered out
    });

    test('loginOffline stores local session token in secure storage', () async {
      // Arrange
      const username = 'sessionuser';
      const password = 'sessionpass';
      final passwordHash = hashPassword(password, username);

      await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-session'),
            username: username,
            passwordHash: passwordHash,
            fullName: const Value('Session User'),
            role: UserRole.superadmin,
            storeId: const Value(1),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Act
      final result = await authService.loginOffline(username, password);

      // Assert
      expect(result.success, isTrue);
      final storedSession = await secureStorage.read(key: 'local_session');
      expect(storedSession, isNotNull);

      // Decode and verify session token contains correct user info
      final decoded = utf8.decode(base64Decode(storedSession!));
      final payload = jsonDecode(decoded) as Map<String, dynamic>;
      expect(payload['username'], equals(username));
      expect(payload['role'], equals('superadmin'));
    });

    test('loginOffline works for all user roles', () async {
      // Test each role can login offline
      final roles = [UserRole.superadmin, UserRole.admin, UserRole.cashier];

      for (final role in roles) {
        final username = 'user_${role.name}';
        final password = 'pass_${role.name}';
        final passwordHash = hashPassword(password, username);

        await db.into(db.users).insert(UsersCompanion.insert(
              clientId: Value('client-${role.name}'),
              username: username,
              passwordHash: passwordHash,
              fullName: Value('Test ${role.name}'),
              role: role,
              storeId: const Value(1),
              isActive: const Value(true),
              syncStatus: const Value(SyncStatus.synced),
              isLocalOnly: const Value(false),
            ));

        final result = await authService.loginOffline(username, password);

        expect(result.success, isTrue,
            reason: 'Login should succeed for ${role.name}');
        expect(result.user!.role, equals(role),
            reason: 'Role should be ${role.name}');
      }
    });
  });

  group('Offline Logout Tests', () {
    test('logout clears access_token from secure storage', () async {
      // Arrange: Set up tokens
      await secureStorage.write(key: 'access_token', value: 'jwt-token-123');
      await secureStorage.write(
          key: 'local_session', value: 'local-session-456');

      // Act
      await authService.logout();

      // Assert
      final accessToken = await secureStorage.read(key: 'access_token');
      expect(accessToken, isNull);
    });

    test('logout clears local_session from secure storage', () async {
      // Arrange
      await secureStorage.write(key: 'access_token', value: 'jwt-token-123');
      await secureStorage.write(
          key: 'local_session', value: 'local-session-456');

      // Act
      await authService.logout();

      // Assert
      final localSession = await secureStorage.read(key: 'local_session');
      expect(localSession, isNull);
    });

    test('logout preserves user data in local database', () async {
      // Arrange: Create user and login
      const username = 'persistuser';
      const password = 'persistpass';
      final passwordHash = hashPassword(password, username);

      await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-persist'),
            username: username,
            passwordHash: passwordHash,
            fullName: const Value('Persistent User'),
            role: UserRole.admin,
            storeId: const Value(1),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Login first
      await authService.loginOffline(username, password);

      // Act
      await authService.logout();

      // Assert: User should still exist in DB for future offline logins
      final user = await (db.select(db.users)
            ..where((u) => u.username.equals(username)))
          .getSingleOrNull();
      expect(user, isNotNull);
      expect(user!.username, equals(username));
    });

    test('logout can be called multiple times without error', () async {
      // Arrange
      await secureStorage.write(key: 'access_token', value: 'token');
      await secureStorage.write(key: 'local_session', value: 'session');

      // Act & Assert: Multiple logouts should not throw
      await authService.logout();
      await authService.logout();
      await authService.logout();

      // Verify storage is cleared
      expect(await secureStorage.read(key: 'access_token'), isNull);
      expect(await secureStorage.read(key: 'local_session'), isNull);
    });

    test('logout works even when no tokens exist', () async {
      // Act & Assert: Logout should not throw when storage is empty
      await authService.logout();

      expect(await secureStorage.read(key: 'access_token'), isNull);
      expect(await secureStorage.read(key: 'local_session'), isNull);
    });
  });

  group('Login then Logout Flow Tests', () {
    test('can login offline, logout, then login again', () async {
      // Arrange
      const username = 'reloginuser';
      const password = 'reloginpass';
      final passwordHash = hashPassword(password, username);

      await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-relogin'),
            username: username,
            passwordHash: passwordHash,
            fullName: const Value('Re-login User'),
            role: UserRole.cashier,
            storeId: const Value(1),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Act 1: First login
      final result1 = await authService.loginOffline(username, password);
      expect(result1.success, isTrue);

      // Get the first session token
      final session1 = await secureStorage.read(key: 'local_session');
      expect(session1, isNotNull);

      // Act 2: Logout
      await authService.logout();
      expect(await secureStorage.read(key: 'local_session'), isNull);

      // Act 3: Login again
      final result2 = await authService.loginOffline(username, password);
      expect(result2.success, isTrue);

      // New session should be created
      final session2 = await secureStorage.read(key: 'local_session');
      expect(session2, isNotNull);
    });

    test('getCurrentUser returns null after logout', () async {
      // Arrange
      const username = 'currentuser';
      const password = 'currentpass';
      final passwordHash = hashPassword(password, username);

      await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-current'),
            username: username,
            passwordHash: passwordHash,
            fullName: const Value('Current User'),
            role: UserRole.admin,
            storeId: const Value(1),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Login
      await authService.loginOffline(username, password);

      // Verify user is logged in
      final userBefore = await authService.getCurrentUser();
      expect(userBefore, isNotNull);

      // Logout
      await authService.logout();

      // Verify user is null after logout
      final userAfter = await authService.getCurrentUser();
      expect(userAfter, isNull);
    });

    test('getCurrentUser returns user after offline login', () async {
      // Arrange
      const username = 'getuser';
      const password = 'getpass';
      final passwordHash = hashPassword(password, username);

      await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-get'),
            serverId: const Value(42),
            username: username,
            passwordHash: passwordHash,
            fullName: const Value('Get User'),
            role: UserRole.superadmin,
            storeId: const Value(1),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Login
      final result = await authService.loginOffline(username, password);
      expect(result.success, isTrue);

      // Get current user
      final currentUser = await authService.getCurrentUser();

      expect(currentUser, isNotNull);
      expect(currentUser!.username, equals(username));
      expect(currentUser.role, equals(UserRole.superadmin));
    });
  });

  group('Ghost User (Local-Only User) Tests', () {
    test('can create and login as ghost user offline', () async {
      // Arrange: Create ghost user
      final createResult = await authService.createGhostUser(
        username: 'ghostuser',
        password: 'ghostpass',
        fullName: 'Ghost User',
        role: UserRole.cashier,
        storeId: 1,
      );

      expect(createResult.success, isTrue);
      expect(createResult.user, isNotNull);
      expect(createResult.user!.isLocalOnly, isTrue);

      // Act: Login as ghost user
      final loginResult =
          await authService.loginOffline('ghostuser', 'ghostpass');

      // Assert
      expect(loginResult.success, isTrue);
      expect(loginResult.user!.username, equals('ghostuser'));
      expect(loginResult.user!.role, equals(UserRole.cashier));
    });

    test('createGhostUser fails if username already exists', () async {
      // Arrange: Create first user
      await authService.createGhostUser(
        username: 'duplicateuser',
        password: 'pass1',
        fullName: 'First User',
        role: UserRole.cashier,
      );

      // Act: Try to create another user with same username
      final result = await authService.createGhostUser(
        username: 'duplicateuser',
        password: 'pass2',
        fullName: 'Second User',
        role: UserRole.admin,
      );

      // Assert
      expect(result.success, isFalse);
      expect(result.message, contains('already exists'));
    });
  });

  group('Password Change Tests', () {
    test('can change password and login with new password offline', () async {
      // Arrange: Create user
      const username = 'pwduser';
      const oldPassword = 'oldpassword';
      const newPassword = 'newpassword';
      final oldHash = hashPassword(oldPassword, username);

      final userId = await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-pwd'),
            username: username,
            passwordHash: oldHash,
            fullName: const Value('Password User'),
            role: UserRole.admin,
            storeId: const Value(1),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Act: Change password
      final changeResult = await authService.changePassword(
        userId: userId,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );

      expect(changeResult.success, isTrue);

      // Assert: Old password should no longer work
      final oldLoginResult =
          await authService.loginOffline(username, oldPassword);
      expect(oldLoginResult.success, isFalse);

      // New password should work
      final newLoginResult =
          await authService.loginOffline(username, newPassword);
      expect(newLoginResult.success, isTrue);
    });

    test('changePassword fails with incorrect old password', () async {
      // Arrange
      const username = 'pwduser2';
      const correctPassword = 'correctpass';
      final passwordHash = hashPassword(correctPassword, username);

      final userId = await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-pwd2'),
            username: username,
            passwordHash: passwordHash,
            fullName: const Value('Password User 2'),
            role: UserRole.cashier,
            storeId: const Value(1),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Act
      final result = await authService.changePassword(
        userId: userId,
        oldPassword: 'wrongoldpassword',
        newPassword: 'newpassword',
      );

      // Assert
      expect(result.success, isFalse);
      expect(result.message, contains('incorrect'));
    });
  });

  group('Edge Cases', () {
    test('loginOffline handles special characters in password', () async {
      // Arrange
      const username = 'specialuser';
      const password = 'p@ss\$w0rd!#%^&*()_+-=[]{}|;:\'"<>,.?/\\`~';
      final passwordHash = hashPassword(password, username);

      await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-special'),
            username: username,
            passwordHash: passwordHash,
            fullName: const Value('Special User'),
            role: UserRole.admin,
            storeId: const Value(1),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Act
      final result = await authService.loginOffline(username, password);

      // Assert
      expect(result.success, isTrue);
    });

    test('loginOffline handles unicode characters in username and password',
        () async {
      // Arrange
      const username = 'ユーザー名'; // Japanese username
      const password = 'пароль密码'; // Russian + Chinese password
      final passwordHash = hashPassword(password, username);

      await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-unicode'),
            username: username,
            passwordHash: passwordHash,
            fullName: const Value('Unicode User'),
            role: UserRole.cashier,
            storeId: const Value(1),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Act
      final result = await authService.loginOffline(username, password);

      // Assert
      expect(result.success, isTrue);
    });

    test(
        'loginOffline is case-sensitive for password but uses lowercase username for hash',
        () async {
      // Arrange
      const username = 'CaseUser';
      const password = 'CaseSensitivePass';
      final passwordHash =
          hashPassword(password, username); // Uses username.toLowerCase()

      await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-case'),
            username: username,
            passwordHash: passwordHash,
            fullName: const Value('Case User'),
            role: UserRole.admin,
            storeId: const Value(1),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Act & Assert: Correct case should work
      final correctResult = await authService.loginOffline(username, password);
      expect(correctResult.success, isTrue);

      // Wrong case password should fail
      final wrongCaseResult =
          await authService.loginOffline(username, 'casesensitivepass');
      expect(wrongCaseResult.success, isFalse);
    });

    test('loginOffline handles empty password gracefully', () async {
      // Arrange: User with empty password (shouldn't happen in practice)
      const username = 'emptypassuser';
      const password = '';
      final passwordHash = hashPassword(password, username);

      await db.into(db.users).insert(UsersCompanion.insert(
            clientId: const Value('client-empty'),
            username: username,
            passwordHash: passwordHash,
            fullName: const Value('Empty Pass User'),
            role: UserRole.cashier,
            storeId: const Value(1),
            isActive: const Value(true),
            syncStatus: const Value(SyncStatus.synced),
            isLocalOnly: const Value(false),
          ));

      // Act: Login with empty password
      final result = await authService.loginOffline(username, password);

      // Assert: Should work (empty password matches empty password hash)
      expect(result.success, isTrue);
    });
  });
}
