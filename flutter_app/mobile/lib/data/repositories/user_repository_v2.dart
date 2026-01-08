import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../db/app_database.dart';

/// Repository for user management (admin/cashier creation, updates, deletion)
/// Implements local-first pattern: all writes go to Drift immediately,
/// then enqueue for background sync
class UserRepository {
  final AppDatabase db;

  UserRepository({required this.db});

  /// Helper method to execute database operations with retry logic for database_closed exceptions.
  /// This handles cases where the database connection gets closed due to app lifecycle or memory pressure.
  Future<R> _withDatabaseRetry<R>(Future<R> Function() operation) async {
    try {
      return await operation();
    } on DriftWrappedException catch (e) {
      if (e.toString().contains('database_closed')) {
        debugPrint(
            '🔁 Database connection closed, attempting to reopen and retry');
        try {
          // Force reopen the database connection by accessing it
          await db.customSelect('SELECT 1').get();
          // Retry the operation
          return await operation();
        } catch (retryError) {
          debugPrint('❌ Database retry failed: $retryError');
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  /// Create a new user (admin or cashier)
  /// Works offline - user is marked as "ghost user" until synced
  Future<User> create({
    required String username,
    required String passwordHash,
    required String fullName,
    required UserRole role,
    int? storeId,
  }) async {
    return await _withDatabaseRetry(() async {
      debugPrint('🔵 UserRepository.create() called:');
      debugPrint('   username: $username');
      debugPrint('   fullName: $fullName');
      debugPrint('   role: ${role.name}');
      debugPrint('   storeId: $storeId');

      final clientId = const Uuid().v4();
      debugPrint('   clientId: $clientId');

      // 1. Insert locally (immediate)
      debugPrint('📝 Inserting user into local database...');
      debugPrint(
          '   ⚠️ storeId for FK: $storeId (must be LOCAL store id, not server_id!)');

      int id;
      try {
        id = await db.into(db.users).insert(UsersCompanion.insert(
              clientId: Value(clientId),
              username: username,
              passwordHash: passwordHash,
              fullName: Value(fullName),
              role: role,
              storeId: Value(storeId),
              isActive: const Value(true),
              syncStatus: const Value(SyncStatus.pending),
              isLocalOnly: const Value(true), // Ghost user until synced
            ));
        debugPrint('✅ User inserted locally with id: $id');
      } catch (e, stackTrace) {
        debugPrint('❌ FAILED to insert user into local database!');
        debugPrint('   Error: $e');
        debugPrint('   This is likely a FOREIGN KEY constraint failure.');
        debugPrint(
            '   store_id $storeId may not exist in the local stores table.');
        debugPrint('   Stack trace: $stackTrace');
        rethrow;
      }

      // 2. Enqueue for sync (background)
      debugPrint('📤 Enqueueing user for sync...');

      // Resolve store ID to server ID if provided
      int? serverStoreId;
      if (storeId != null) {
        final store = await (db.select(db.stores)
              ..where((s) => s.id.equals(storeId)))
            .getSingleOrNull();
        serverStoreId = store?.serverId;
        debugPrint(
            'UserRepository.create: Resolved local storeId $storeId to server storeId $serverStoreId');
        if (serverStoreId == null) {
          debugPrint(
              '⚠️ UserRepository.create: Store $storeId has no serverId - user will be created without store assignment until store syncs');
        }
      }

      try {
        await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
              clientTempId: Value(clientId),
              resourceType: 'user',
              operation: 'create',
              entityId: Value(id.toString()),
              // CRITICAL: Include resource_type and operation at top level to match sync service expected format
              payloadJson: jsonEncode({
                'resource_type': 'user',
                'operation': 'create',
                'temp_id': clientId,
                'id': id.toString(),
                'data': {
                  'username': username,
                  'password':
                      passwordHash, // Plain text password - server will hash with bcrypt
                  'full_name': fullName,
                  'role': role.name,
                  if (serverStoreId != null) 'store_id': serverStoreId,
                }
              }),
            ));

        debugPrint(
            '✅ User enqueued for sync: $username (clientId: $clientId, entityId: $id)');
      } catch (e, stackTrace) {
        debugPrint('❌ CRITICAL ERROR enqueueing user for sync: $e');
        debugPrint('Stack trace: $stackTrace');
        debugPrint(
            '⚠️ This might be a database schema issue. Try uninstalling and reinstalling the app.');
        // Don't fail the user creation - user is already in DB
        // Just log the sync error
      }

      // 3. Return immediately - UI never waits for network
      debugPrint('🔄 Fetching created user from database...');
      final createdUser = await getById(id);
      debugPrint(
          '✅ User created successfully: ${createdUser.username} (id: ${createdUser.id})');
      return createdUser;
    });
  }

  /// Update user information
  Future<User> update({
    required int id,
    String? fullName,
    UserRole? role,
    int? storeId,
    bool? isActive,
    bool? mustChangePassword,
  }) async {
    return await _withDatabaseRetry(() async {
      final user = await getById(id);

      // 1. Update locally
      await (db.update(db.users)..where((u) => u.id.equals(id)))
          .write(UsersCompanion(
        fullName: fullName != null ? Value(fullName) : const Value.absent(),
        role: role != null ? Value(role) : const Value.absent(),
        storeId: storeId != null ? Value(storeId) : const Value.absent(),
        isActive: isActive != null ? Value(isActive) : const Value.absent(),
        mustChangePassword: mustChangePassword != null
            ? Value(mustChangePassword)
            : const Value.absent(),
        syncStatus: const Value(SyncStatus.pending),
        lastUpdatedAt: Value(DateTime.now()),
      ));

      // 2. Enqueue sync
      final updatedUser = await getById(id);

      // Resolve store ID to server ID if provided
      int? serverStoreId;
      if (storeId != null) {
        final store = await (db.select(db.stores)
              ..where((s) => s.id.equals(storeId)))
            .getSingleOrNull();
        serverStoreId = store?.serverId;
        debugPrint(
            'UserRepository.update: Resolved local storeId $storeId to server storeId $serverStoreId');
        if (serverStoreId == null) {
          debugPrint(
              '⚠️ UserRepository.update: Store $storeId has no serverId - user assignment will be deferred until store syncs');
        }
      }

      await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
            resourceType: 'user',
            operation: 'update',
            entityId: Value(user.serverId?.toString() ?? user.clientId),
            // CRITICAL: Include resource_type and operation at top level to match sync service expected format
            payloadJson: jsonEncode({
              'resource_type': 'user',
              'operation': 'update',
              'id': user.serverId?.toString() ?? user.clientId,
              'data': {
                'id': user.serverId,
                'client_id': user.clientId,
                if (fullName != null) 'full_name': fullName,
                if (role != null) 'role': role.name,
                if (serverStoreId != null) 'store_id': serverStoreId,
                if (isActive != null) 'is_active': isActive,
                if (mustChangePassword != null)
                  'must_change_password': mustChangePassword,
              }
            }),
          ));

      return updatedUser;
    });
  }

  /// Soft delete user (sets isActive to false)
  Future<void> delete(int id) async {
    await update(id: id, isActive: false);
  }

  /// Hard delete user (removes from database - use with caution)
  Future<void> hardDelete(int id) async {
    return await _withDatabaseRetry(() async {
      final user = await getById(id);

      // If user has server ID, enqueue delete operation
      if (user.serverId != null) {
        await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
              resourceType: 'user',
              operation: 'delete',
              entityId: Value(user.serverId.toString()),
              payloadJson: jsonEncode({
                'resource_type': 'user',
                'operation': 'delete',
                'id': user.serverId.toString(),
                'data': {
                  'id': user.serverId,
                }
              }),
            ));
      }

      // Delete locally
      await (db.delete(db.users)..where((u) => u.id.equals(id))).go();
    });
  }

  /// Get user by ID
  Future<User> getById(int id) async {
    return await (db.select(db.users)..where((u) => u.id.equals(id)))
        .getSingle();
  }

  /// Get user by username
  Future<User?> getByUsername(String username) async {
    return await (db.select(db.users)
          ..where((u) => u.username.equals(username)))
        .getSingleOrNull();
  }

  /// Get all users (active only by default)
  Stream<List<User>> watchAll({bool activeOnly = true, int? storeId}) {
    var query = db.select(db.users);

    if (activeOnly) {
      query = query..where((u) => u.isActive.equals(true));
    }

    if (storeId != null) {
      query = query..where((u) => u.storeId.equals(storeId));
    }

    query = query..orderBy([(u) => OrderingTerm.asc(u.username)]);

    return query.watch();
  }

  /// Get all users by role
  Stream<List<User>> watchByRole(UserRole role, {bool activeOnly = true}) {
    var query = db.select(db.users)..where((u) => u.role.equals(role.name));

    if (activeOnly) {
      query = query..where((u) => u.isActive.equals(true));
    }

    query = query..orderBy([(u) => OrderingTerm.asc(u.username)]);

    return query.watch();
  }

  /// Get all cashiers for a specific store
  Stream<List<User>> watchCashiersByStore(int storeId) {
    return (db.select(db.users)
          ..where((u) => u.role.equals(UserRole.cashier.name))
          ..where((u) => u.storeId.equals(storeId))
          ..where((u) => u.isActive.equals(true))
          ..orderBy([(u) => OrderingTerm.asc(u.username)]))
        .watch();
  }

  /// Get all admins
  Stream<List<User>> watchAdmins({bool activeOnly = true}) {
    return watchByRole(UserRole.admin, activeOnly: activeOnly);
  }

  /// Get count of users by role
  Future<int> countByRole(UserRole role, {bool activeOnly = true}) async {
    var query = db.selectOnly(db.users)
      ..addColumns([db.users.id.count()])
      ..where(db.users.role.equals(role.name));

    if (activeOnly) {
      query = query..where(db.users.isActive.equals(true));
    }

    final result = await query.getSingle();
    return result.read(db.users.id.count()) ?? 0;
  }

  /// Check if username already exists
  Future<bool> usernameExists(String username, {int? excludeUserId}) async {
    var query = db.select(db.users)..where((u) => u.username.equals(username));

    if (excludeUserId != null) {
      query = query..where((u) => u.id.isNotValue(excludeUserId));
    }

    final user = await query.getSingleOrNull();
    return user != null;
  }

  /// Get users pending sync (ghost users)
  Future<List<User>> getPendingSync() async {
    return await (db.select(db.users)
          ..where((u) => u.syncStatus.equals(SyncStatus.pending.name)))
        .get();
  }

  /// Get users with sync errors
  Future<List<User>> getSyncErrors() async {
    return await (db.select(db.users)
          ..where((u) => u.syncStatus.equals(SyncStatus.error.name)))
        .get();
  }

  /// Assign user to store
  Future<User> assignToStore(int userId, int storeId) async {
    return await update(id: userId, storeId: storeId);
  }

  /// Remove user from store (set storeId to null)
  Future<User> removeFromStore(int userId) async {
    return await _withDatabaseRetry(() async {
      final user = await getById(userId);

      await (db.update(db.users)..where((u) => u.id.equals(userId)))
          .write(UsersCompanion(
        storeId: const Value(null),
        syncStatus: const Value(SyncStatus.pending),
        lastUpdatedAt: Value(DateTime.now()),
      ));

      await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
            resourceType: 'user',
            operation: 'update',
            entityId: Value(user.serverId?.toString() ?? user.clientId),
            // CRITICAL: Include resource_type and operation at top level to match sync service expected format
            payloadJson: jsonEncode({
              'resource_type': 'user',
              'operation': 'update',
              'id': user.serverId?.toString() ?? user.clientId,
              'data': {
                'id': user.serverId,
                'client_id': user.clientId,
                'store_id': null,
              }
            }),
          ));

      return await getById(userId);
    });
  }

  /// Force password change on next login
  Future<User> requirePasswordChange(int userId) async {
    return await update(id: userId, mustChangePassword: true);
  }
}
