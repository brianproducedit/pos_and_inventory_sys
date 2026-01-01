import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../../../lib/db/app_database.dart';
import '../../../lib/data/repositories/user_repository_v2.dart';

void main() {
  late AppDatabase database;
  late UserRepository userRepository;

  setUp(() async {
    // Create in-memory database for testing
    database = AppDatabase(NativeDatabase.memory());
    userRepository = UserRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  group('UserRepository V2 - CRUD Operations', () {
    test('create should create user and enqueue sync', () async {
      final userId = await userRepository.create(
        username: 'testuser',
        password: 'Test123!',
        fullName: 'Test User',
        role: UserRole.cashier,
        storeId: null,
      );

      expect(userId, greaterThan(0));

      // Verify user was created
      final user = await userRepository.getById(userId);
      expect(user, isNotNull);
      expect(user!.username, 'testuser');
      expect(user.fullName, 'Test User');
      expect(user.role, UserRole.cashier);
      expect(user.syncStatus, SyncStatus.pending);
      expect(user.isLocalOnly, false);

      // Verify password hash
      expect(user.passwordHash, _hashPassword('Test123!'));

      // Verify sync queue entry
      final syncItems = await (database.select(database.syncQueue)
            ..where((q) => q.resourceType.equals('user'))
            ..where((q) => q.resourceId.equals(userId)))
          .get();
      expect(syncItems.length, 1);
      expect(syncItems.first.operation, 'create');
      expect(syncItems.first.status, 'pending');
    });

    test('getById should return user by id', () async {
      final userId = await userRepository.create(
        username: 'getbyid',
        password: 'Pass123!',
        fullName: 'Get By ID',
        role: UserRole.admin,
        storeId: null,
      );

      final user = await userRepository.getById(userId);
      expect(user, isNotNull);
      expect(user!.id, userId);
      expect(user.username, 'getbyid');
    });

    test('getById should return null for non-existent user', () async {
      final user = await userRepository.getById(99999);
      expect(user, isNull);
    });

    test('getByUsername should return user by username', () async {
      await userRepository.create(
        username: 'findme',
        password: 'Pass123!',
        fullName: 'Find Me',
        role: UserRole.cashier,
        storeId: null,
      );

      final user = await userRepository.getByUsername('findme');
      expect(user, isNotNull);
      expect(user!.username, 'findme');
      expect(user.fullName, 'Find Me');
    });

    test('getByUsername should return null for non-existent username', () async {
      final user = await userRepository.getByUsername('nonexistent');
      expect(user, isNull);
    });

    test('getAll should return all active users', () async {
      await userRepository.create(
        username: 'user1',
        password: 'Pass123!',
        fullName: 'User 1',
        role: UserRole.cashier,
        storeId: null,
      );
      
      await userRepository.create(
        username: 'user2',
        password: 'Pass123!',
        fullName: 'User 2',
        role: UserRole.admin,
        storeId: null,
      );

      final users = await userRepository.getAll();
      expect(users.length, greaterThanOrEqualTo(2));
      expect(users.any((u) => u.username == 'user1'), true);
      expect(users.any((u) => u.username == 'user2'), true);
    });

    test('update should update user and enqueue sync', () async {
      final userId = await userRepository.create(
        username: 'updateme',
        password: 'Pass123!',
        fullName: 'Original Name',
        role: UserRole.cashier,
        storeId: null,
      );

      await userRepository.update(
        userId,
        fullName: 'Updated Name',
        role: UserRole.admin,
      );

      final user = await userRepository.getById(userId);
      expect(user!.fullName, 'Updated Name');
      expect(user.role, UserRole.admin);
      expect(user.syncStatus, SyncStatus.pending);

      // Verify sync queue has update operation
      final syncItems = await (database.select(database.syncQueue)
            ..where((q) => q.resourceType.equals('user'))
            ..where((q) => q.resourceId.equals(userId))
            ..where((q) => q.operation.equals('update')))
          .get();
      expect(syncItems.length, greaterThanOrEqualTo(1));
    });

    test('changePassword should update password hash and enqueue sync', () async {
      final userId = await userRepository.create(
        username: 'passchange',
        password: 'OldPass123!',
        fullName: 'Pass Change',
        role: UserRole.cashier,
        storeId: null,
      );

      final oldUser = await userRepository.getById(userId);
      final oldHash = oldUser!.passwordHash;

      await userRepository.changePassword(userId, 'NewPass456!');

      final updatedUser = await userRepository.getById(userId);
      expect(updatedUser!.passwordHash, isNot(oldHash));
      expect(updatedUser.passwordHash, _hashPassword('NewPass456!'));
      expect(updatedUser.syncStatus, SyncStatus.pending);
    });

    test('deactivate should mark user as inactive and enqueue sync', () async {
      final userId = await userRepository.create(
        username: 'deactivateme',
        password: 'Pass123!',
        fullName: 'Deactivate Me',
        role: UserRole.cashier,
        storeId: null,
      );

      await userRepository.deactivate(userId);

      final user = await userRepository.getById(userId);
      expect(user!.isActive, false);
      expect(user.syncStatus, SyncStatus.pending);
    });

    test('activate should mark user as active and enqueue sync', () async {
      final userId = await userRepository.create(
        username: 'reactivateme',
        password: 'Pass123!',
        fullName: 'Reactivate Me',
        role: UserRole.cashier,
        storeId: null,
      );

      await userRepository.deactivate(userId);
      await userRepository.activate(userId);

      final user = await userRepository.getById(userId);
      expect(user!.isActive, true);
      expect(user.syncStatus, SyncStatus.pending);
    });

    test('delete should soft delete user and enqueue sync', () async {
      final userId = await userRepository.create(
        username: 'deleteme',
        password: 'Pass123!',
        fullName: 'Delete Me',
        role: UserRole.cashier,
        storeId: null,
      );

      await userRepository.delete(userId);

      // User should still exist but be inactive
      final user = await userRepository.getById(userId);
      expect(user!.isActive, false);
      expect(user.syncStatus, SyncStatus.pending);

      // Verify sync queue has delete operation
      final syncItems = await (database.select(database.syncQueue)
            ..where((q) => q.resourceType.equals('user'))
            ..where((q) => q.resourceId.equals(userId))
            ..where((q) => q.operation.equals('delete')))
          .get();
      expect(syncItems.length, greaterThanOrEqualTo(1));
    });
  });

  group('UserRepository V2 - Store Filtering', () {
    test('getByStore should return only users for specified store', () async {
      // Create store
      await database.into(database.stores).insert(StoresCompanion.insert(
        clientId: Value('store1'),
        name: 'Test Store 1',
      ));
      final storeId = (await database.select(database.stores).getSingle()).id;

      // Create users for store
      await userRepository.create(
        username: 'storeuser1',
        password: 'Pass123!',
        fullName: 'Store User 1',
        role: UserRole.cashier,
        storeId: storeId,
      );

      await userRepository.create(
        username: 'storeuser2',
        password: 'Pass123!',
        fullName: 'Store User 2',
        role: UserRole.cashier,
        storeId: storeId,
      );

      // Create user for different store
      await userRepository.create(
        username: 'otheruser',
        password: 'Pass123!',
        fullName: 'Other User',
        role: UserRole.cashier,
        storeId: null,
      );

      final storeUsers = await userRepository.getByStore(storeId);
      expect(storeUsers.length, 2);
      expect(storeUsers.every((u) => u.storeId == storeId), true);
    });
  });

  group('UserRepository V2 - Role Filtering', () {
    test('getByRole should return only users with specified role', () async {
      await userRepository.create(
        username: 'admin1',
        password: 'Pass123!',
        fullName: 'Admin 1',
        role: UserRole.admin,
        storeId: null,
      );

      await userRepository.create(
        username: 'cashier1',
        password: 'Pass123!',
        fullName: 'Cashier 1',
        role: UserRole.cashier,
        storeId: null,
      );

      final admins = await userRepository.getByRole(UserRole.admin);
      expect(admins.length, greaterThanOrEqualTo(1));
      expect(admins.every((u) => u.role == UserRole.admin), true);
    });
  });

  group('UserRepository V2 - Sync Status', () {
    test('getPendingSyncUsers should return users with pending sync', () async {
      await userRepository.create(
        username: 'pending1',
        password: 'Pass123!',
        fullName: 'Pending 1',
        role: UserRole.cashier,
        storeId: null,
      );

      final pendingUsers = await userRepository.getPendingSyncUsers();
      expect(pendingUsers.length, greaterThanOrEqualTo(1));
      expect(pendingUsers.every((u) => u.syncStatus == SyncStatus.pending), true);
    });

    test('markAsSynced should update sync status', () async {
      final userId = await userRepository.create(
        username: 'tosync',
        password: 'Pass123!',
        fullName: 'To Sync',
        role: UserRole.cashier,
        storeId: null,
      );

      await userRepository.markAsSynced(userId, serverId: 100);

      final user = await userRepository.getById(userId);
      expect(user!.syncStatus, SyncStatus.synced);
      expect(user.serverId, 100);
    });
  });

  group('UserRepository V2 - Password Validation', () {
    test('validatePassword should return true for correct password', () async {
      final userId = await userRepository.create(
        username: 'validpass',
        password: 'Correct123!',
        fullName: 'Valid Pass',
        role: UserRole.cashier,
        storeId: null,
      );

      final isValid = await userRepository.validatePassword(userId, 'Correct123!');
      expect(isValid, true);
    });

    test('validatePassword should return false for incorrect password', () async {
      final userId = await userRepository.create(
        username: 'invalidpass',
        password: 'Correct123!',
        fullName: 'Invalid Pass',
        role: UserRole.cashier,
        storeId: null,
      );

      final isValid = await userRepository.validatePassword(userId, 'Wrong123!');
      expect(isValid, false);
    });
  });

  group('UserRepository V2 - Error Handling', () {
    test('create should throw on duplicate username', () async {
      await userRepository.create(
        username: 'duplicate',
        password: 'Pass123!',
        fullName: 'First User',
        role: UserRole.cashier,
        storeId: null,
      );

      expect(
        () => userRepository.create(
          username: 'duplicate',
          password: 'Pass123!',
          fullName: 'Second User',
          role: UserRole.cashier,
          storeId: null,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('update should throw for non-existent user', () async {
      expect(
        () => userRepository.update(99999, fullName: 'Updated'),
        throwsA(isA<Exception>()),
      );
    });

    test('delete should throw for non-existent user', () async {
      expect(
        () => userRepository.delete(99999),
        throwsA(isA<Exception>()),
      );
    });
  });
}
