import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../db/app_database.dart';

/// Repository for user management (admin/cashier creation, updates, deletion)
/// Implements local-first pattern: all writes go to Drift immediately,
/// then enqueue for background sync
class UserRepository {
  final AppDatabase db;

  UserRepository({required this.db});

  /// Create a new user (admin or cashier)
  /// Works offline - user is marked as "ghost user" until synced
  Future<User> create({
    required String username,
    required String passwordHash,
    required String fullName,
    required UserRole role,
    int? storeId,
  }) async {
    final clientId = const Uuid().v4();

    // 1. Insert locally (immediate)
    final id = await db.into(db.users).insert(UsersCompanion.insert(
          clientId: Value(clientId),
          username: username,
          passwordHash: passwordHash,
          fullName: Value(fullName),
          role: role,
          storeId: Value(storeId),
          isActive: Value(true),
          syncStatus: Value(SyncStatus.pending),
          isLocalOnly: Value(true), // Ghost user until synced
        ));

    // 2. Enqueue for sync (background)
    await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
          clientTempId: Value(clientId),
          resourceType: 'user',
          operation: 'create',
          entityId: Value(id.toString()),
          payloadJson: jsonEncode({
            'username': username,
            'full_name': fullName,
            'role': role.name,
            'store_id': storeId,
            // Note: password_hash sent to server needs special handling
            // Server should receive plain password for proper bcrypt hashing
          }),
        ));

    // 3. Return immediately - UI never waits for network
    return await getById(id);
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
    final user = await getById(id);

    // 1. Update locally
    await (db.update(db.users)..where((u) => u.id.equals(id)))
        .write(UsersCompanion(
      fullName: fullName != null ? Value(fullName) : Value.absent(),
      role: role != null ? Value(role) : Value.absent(),
      storeId: storeId != null ? Value(storeId) : Value.absent(),
      isActive: isActive != null ? Value(isActive) : Value.absent(),
      mustChangePassword: mustChangePassword != null
          ? Value(mustChangePassword)
          : Value.absent(),
      syncStatus: Value(SyncStatus.pending),
      lastUpdatedAt: Value(DateTime.now()),
    ));

    // 2. Enqueue sync
    final updatedUser = await getById(id);
    await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
          resourceType: 'user',
          operation: 'update',
          entityId: Value(user.serverId?.toString() ?? user.clientId),
          payloadJson: jsonEncode({
            'id': user.serverId,
            'client_id': user.clientId,
            if (fullName != null) 'full_name': fullName,
            if (role != null) 'role': role.name,
            if (storeId != null) 'store_id': storeId,
            if (isActive != null) 'is_active': isActive,
            if (mustChangePassword != null)
              'must_change_password': mustChangePassword,
          }),
        ));

    return updatedUser;
  }

  /// Soft delete user (sets isActive to false)
  Future<void> delete(int id) async {
    await update(id: id, isActive: false);
  }

  /// Hard delete user (removes from database - use with caution)
  Future<void> hardDelete(int id) async {
    final user = await getById(id);

    // If user has server ID, enqueue delete operation
    if (user.serverId != null) {
      await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
            resourceType: 'user',
            operation: 'delete',
            entityId: Value(user.serverId.toString()),
            payloadJson: jsonEncode({
              'id': user.serverId,
            }),
          ));
    }

    // Delete locally
    await (db.delete(db.users)..where((u) => u.id.equals(id))).go();
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
    final user = await getById(userId);

    await (db.update(db.users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(
      storeId: Value(null),
      syncStatus: Value(SyncStatus.pending),
      lastUpdatedAt: Value(DateTime.now()),
    ));

    await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
          resourceType: 'user',
          operation: 'update',
          entityId: Value(user.serverId?.toString() ?? user.clientId),
          payloadJson: jsonEncode({
            'id': user.serverId,
            'client_id': user.clientId,
            'store_id': null,
          }),
        ));

    return await getById(userId);
  }

  /// Force password change on next login
  Future<User> requirePasswordChange(int userId) async {
    return await update(id: userId, mustChangePassword: true);
  }
}
