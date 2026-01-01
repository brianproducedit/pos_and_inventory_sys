import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';
import '../db/app_database.dart';
import '../data/remote/api_client.dart';
import 'connectivity_monitor.dart';

/// Result of authentication attempt
class AuthResult {
  final bool success;
  final String? message;
  final User? user;
  final String? token;

  AuthResult._({
    required this.success,
    this.message,
    this.user,
    this.token,
  });

  factory AuthResult.success(User user, {String? token}) {
    return AuthResult._(
      success: true,
      user: user,
      token: token,
      message: 'Login successful',
    );
  }

  factory AuthResult.failure(String message) {
    return AuthResult._(
      success: false,
      message: message,
    );
  }
}

/// Offline-first authentication service
/// Implements "Indestructible Identity" pattern from V2 roadmap
class OfflineAuthService {
  final AppDatabase db;
  final ApiClient apiClient;
  final FlutterSecureStorage secureStorage;

  OfflineAuthService({
    required this.db,
    required this.apiClient,
    FlutterSecureStorage? storage,
  }) : secureStorage = storage ?? const FlutterSecureStorage();

  /// Main login entry point - decides online vs offline
  Future<AuthResult> login(String username, String password) async {
    final hasConnectivity = await ConnectivityMonitor().checkActualConnectivity();

    if (hasConnectivity) {
      try {
        return await loginOnline(username, password);
      } catch (e) {
        // Server unreachable, fall back to offline
        print('Online login failed: $e, falling back to offline');
        return await loginOffline(username, password);
      }
    } else {
      return await loginOffline(username, password);
    }
  }

  /// Online login: authenticate with server, cache credentials locally
  Future<AuthResult> loginOnline(String username, String password) async {
    // 1. Call FastAPI /auth/token
    final response = await apiClient.login(username, password);

    // 2. Store JWT securely
    await secureStorage.write(key: 'access_token', value: response.accessToken);

    // 3. Fetch full user info
    final userInfo = await apiClient.getUserInfo(response.accessToken);

    // 4. Hash password for offline storage (SHA-256 + salt)
    final passwordHash = _hashPassword(password, username);

    // 5. Store user in local DB for offline access
    final existingUser = await (db.select(db.users)
          ..where((u) => u.serverId.equals(userInfo.id)))
        .getSingleOrNull();

    if (existingUser != null) {
      // Update existing user
      await (db.update(db.users)..where((u) => u.id.equals(existingUser.id)))
          .write(UsersCompanion(
        username: Value(username),
        passwordHash: Value(passwordHash),
        fullName: Value(userInfo.fullName),
        role: Value(_parseRole(userInfo.role)),
        storeId: Value(userInfo.storeId),
        isActive: Value(true),
        syncStatus: Value(SyncStatus.synced),
        isLocalOnly: Value(false),
        lastUpdatedAt: Value(DateTime.now()),
      ));
    } else {
      // Insert new user
      await db.into(db.users).insert(UsersCompanion.insert(
            serverId: Value(userInfo.id),
            username: username,
            passwordHash: passwordHash,
            fullName: Value(userInfo.fullName),
            role: _parseRole(userInfo.role),
            storeId: Value(userInfo.storeId),
            isActive: Value(true),
            syncStatus: Value(SyncStatus.synced),
            isLocalOnly: Value(false),
          ));
    }

    // Get the stored user
    final storedUser = await (db.select(db.users)
          ..where((u) => u.username.equals(username)))
        .getSingle();

    return AuthResult.success(storedUser, token: response.accessToken);
  }

  /// Offline login: validate against locally stored credentials
  Future<AuthResult> loginOffline(String username, String password) async {
    // 1. Find user in local DB
    final user = await (db.select(db.users)
          ..where((u) => u.username.equals(username))
          ..where((u) => u.isActive.equals(true)))
        .getSingleOrNull();

    if (user == null) {
      return AuthResult.failure(
          'User not found. Please login online first.');
    }

    // 2. Verify password hash
    final inputHash = _hashPassword(password, username);
    if (inputHash != user.passwordHash) {
      return AuthResult.failure('Invalid password');
    }

    // 3. Generate local session token (for app state management)
    final localToken = _generateLocalSessionToken(user);
    await secureStorage.write(key: 'local_session', value: localToken);

    return AuthResult.success(user, token: localToken);
  }

  /// Create user locally when offline (Ghost User)
  Future<AuthResult> createGhostUser({
    required String username,
    required String password,
    required String fullName,
    required UserRole role,
    int? storeId,
  }) async {
    // Check if username already exists
    final existing = await (db.select(db.users)
          ..where((u) => u.username.equals(username)))
        .getSingleOrNull();

    if (existing != null) {
      return AuthResult.failure('Username already exists');
    }

    final clientId = const Uuid().v4();
    final passwordHash = _hashPassword(password, username);

    // Insert user locally
    final id = await db.into(db.users).insert(UsersCompanion.insert(
          clientId: Value(clientId),
          username: username,
          passwordHash: passwordHash,
          fullName: Value(fullName),
          role: role,
          storeId: Value(storeId),
          isActive: Value(true),
          syncStatus: Value(SyncStatus.pending),
          isLocalOnly: Value(true), // Mark as ghost user
        ));

    // Enqueue for sync
    await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
          clientTempId: Value(clientId),
          resourceType: 'user',
          operation: 'create',
          entityId: Value(id.toString()),
          payloadJson: jsonEncode({
            'username': username,
            'password': password, // Send plain text to server for proper hashing
            'full_name': fullName,
            'role': role.name,
            'store_id': storeId,
          }),
        ));

    final user =
        await (db.select(db.users)..where((u) => u.id.equals(id))).getSingle();

    return AuthResult.success(user);
  }

  /// Change user password
  Future<AuthResult> changePassword({
    required int userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    final user =
        await (db.select(db.users)..where((u) => u.id.equals(userId)))
            .getSingleOrNull();

    if (user == null) {
      return AuthResult.failure('User not found');
    }

    // Verify old password
    final oldHash = _hashPassword(oldPassword, user.username);
    if (oldHash != user.passwordHash) {
      return AuthResult.failure('Current password is incorrect');
    }

    // Hash new password
    final newHash = _hashPassword(newPassword, user.username);

    // Update locally
    await (db.update(db.users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(
      passwordHash: Value(newHash),
      mustChangePassword: Value(false),
      syncStatus: Value(SyncStatus.pending),
      lastUpdatedAt: Value(DateTime.now()),
    ));

    // Enqueue password change for sync
    await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
          resourceType: 'user',
          operation: 'update',
          entityId: Value(user.serverId?.toString() ?? user.clientId),
          payloadJson: jsonEncode({
            'id': user.serverId,
            'client_id': user.clientId,
            'password': newPassword, // Send plain text to server
            'action': 'change_password',
          }),
        ));

    final updatedUser =
        await (db.select(db.users)..where((u) => u.id.equals(userId)))
            .getSingle();

    return AuthResult.success(updatedUser);
  }

  /// Logout - clear tokens but keep user data
  Future<void> logout() async {
    await secureStorage.delete(key: 'access_token');
    await secureStorage.delete(key: 'local_session');
  }

  /// Get current authenticated user from secure storage
  Future<User?> getCurrentUser() async {
    // Try to get local session first
    final localSession = await secureStorage.read(key: 'local_session');
    if (localSession != null) {
      final userId = _extractUserIdFromToken(localSession);
      if (userId != null) {
        return await (db.select(db.users)..where((u) => u.id.equals(userId)))
            .getSingleOrNull();
      }
    }

    // Try to get from access token
    final accessToken = await secureStorage.read(key: 'access_token');
    if (accessToken != null) {
      // For JWT, we'd decode it here
      // For now, just fetch the most recent active user
      return await (db.select(db.users)
            ..where((u) => u.isActive.equals(true))
            ..orderBy([(u) => OrderingTerm.desc(u.lastUpdatedAt)])
            ..limit(1))
          .getSingleOrNull();
    }

    return null;
  }

  /// Hash password with SHA-256 and username as salt
  String _hashPassword(String password, String username) {
    final bytes = utf8.encode(password + username.toLowerCase());
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// Generate local session token
  String _generateLocalSessionToken(User user) {
    final payload = jsonEncode({
      'user_id': user.id,
      'username': user.username,
      'role': user.role.name,
      'exp': DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
    });
    return base64Encode(utf8.encode(payload));
  }

  /// Extract user ID from local session token
  int? _extractUserIdFromToken(String token) {
    try {
      final decoded = utf8.decode(base64Decode(token));
      final payload = jsonDecode(decoded) as Map<String, dynamic>;
      return payload['user_id'] as int?;
    } catch (_) {
      return null;
    }
  }

  /// Parse role string to enum
  UserRole _parseRole(String role) {
    switch (role.toLowerCase()) {
      case 'superadmin':
        return UserRole.superadmin;
      case 'admin':
        return UserRole.admin;
      case 'cashier':
        return UserRole.cashier;
      default:
        return UserRole.cashier;
    }
  }
}
