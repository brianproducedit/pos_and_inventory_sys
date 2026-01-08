import 'dart:async';

import 'package:flutter/foundation.dart';
import '../db/app_database.dart';
import '../data/repositories/user_repository_v2.dart' as v2;
import 'store_provider.dart';
import 'auth_provider.dart';

class UserManagementProvider with ChangeNotifier {
  final v2.UserRepository _userRepository;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _admins = [];
  List<Map<String, dynamic>> _cashiers = [];
  bool _isLoading = false;
  String? _errorMessage;
  StoreProvider? _storeProvider;
  AuthProvider? _authProvider;
  int? _lastStoreId;
  StreamSubscription<List<User>>? _usersSubscription;

  UserManagementProvider({required v2.UserRepository userRepository})
      : _userRepository = userRepository;

  int? _parseStoreId(dynamic id) {
    if (id == null) return null;
    if (id is int) return id;
    return int.tryParse(id.toString());
  }

  void _onStoreChanged() {
    final newId = _parseStoreId(_storeProvider?.currentStore?['id']);
    if (newId != _lastStoreId) {
      _lastStoreId = newId;
      unawaited(loadUsers());
    }
  }

  List<Map<String, dynamic>> get users => _users;
  List<Map<String, dynamic>> get admins => _admins;
  List<Map<String, dynamic>> get cashiers => _cashiers;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void setStoreProvider(StoreProvider storeProvider) {
    if (_storeProvider != null) {
      _storeProvider!.removeListener(_onStoreChanged);
    }
    _storeProvider = storeProvider;
    _lastStoreId = _parseStoreId(_storeProvider?.currentStore?['id']);
    _storeProvider!.addListener(_onStoreChanged);
  }

  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
  }

  Future<void> loadUsers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Cancel previous subscription if any
      await _usersSubscription?.cancel();

      // Determine filtering based on current user's role
      final userRole = _authProvider?.role;
      final userStoreId = _authProvider?.storeId;
      final currentStoreId = _parseStoreId(_storeProvider?.currentStore?['id']);
      int? filterStoreId;

      if (userRole == UserRole.superadmin) {
        // Superadmin sees all users from all stores
        filterStoreId = null;
        debugPrint(
            'UserManagementProvider.loadUsers: superadmin - loading all users');
      } else if (userRole == UserRole.admin && userStoreId != null) {
        // Admin sees only users from their assigned store
        filterStoreId = userStoreId;
        debugPrint(
            'UserManagementProvider.loadUsers: admin - filtering to store_id=$userStoreId');
      } else {
        // Fallback: use current store context (for cashier or when no auth provider set)
        filterStoreId = currentStoreId;
        debugPrint(
            'UserManagementProvider.loadUsers: fallback - using current store context store_id=$filterStoreId');
      }

      // Watch users from local database (works offline!)
      _usersSubscription = _userRepository
          .watchAll(activeOnly: true, storeId: filterStoreId)
          .listen((users) {
        // Convert User objects to Map format for compatibility
        _users = users.map((user) => _userToMap(user)).toList();
        _admins = _users.where((user) => user['role'] == 'admin').toList();
        _cashiers = _users.where((user) => user['role'] == 'cashier').toList();
        notifyListeners();
      });

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load users: $e';
      debugPrint('Error loading users: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Convert User entity to Map for backward compatibility
  Map<String, dynamic> _userToMap(User user) {
    return {
      'id': user.id,
      'server_id': user.serverId,
      'client_id': user.clientId,
      'username': user.username,
      'full_name': user.fullName,
      'role': user.role.name,
      'store_id': user.storeId,
      'is_active': user.isActive,
      'must_change_password': user.mustChangePassword,
      'is_local_only': user.isLocalOnly,
      'sync_status': user.syncStatus.name,
      'created_at': user.createdAt.toIso8601String(),
      'last_updated_at': user.lastUpdatedAt.toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    debugPrint('🔵 UserManagementProvider.createUser() called');
    debugPrint('   userData: $userData');

    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    try {
      // Parse role from string to enum
      final roleStr = userData['role'] as String;
      final role = _parseRole(roleStr);
      debugPrint('   Parsed role: ${role.name}');

      // Get password (plain or hashed) and hash it if needed
      String passwordHash;
      if (userData.containsKey('password_hash')) {
        passwordHash = userData['password_hash'] as String;
      } else if (userData.containsKey('password')) {
        // Plain password provided - hash it (simple hash for now, server will re-hash with bcrypt)
        passwordHash = userData['password'] as String;
      } else {
        passwordHash = 'TEMP_HASH_CHANGE_REQUIRED';
      }

      // Create user using V2 repository (works offline!)
      debugPrint('📤 Calling _userRepository.create()...');
      final newUser = await _userRepository.create(
        username: userData['username'] as String,
        passwordHash: passwordHash,
        fullName: userData['full_name'] as String,
        role: role,
        storeId: userData['store_id'] as int?,
      );
      debugPrint('✅ User created via repository: ${newUser.username}');

      final userMap = _userToMap(newUser);
      // The stream subscription will update _users, _admins, _cashiers

      _isLoading = false;
      notifyListeners();
      return userMap;
    } catch (e) {
      _errorMessage = 'Failed to create user: $e';
      _isLoading = false;
      debugPrint('Error creating user: $e');
      notifyListeners();
      rethrow;
    }
  }

  UserRole _parseRole(String roleStr) {
    switch (roleStr.toLowerCase()) {
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

  Future<Map<String, dynamic>> updateUser(
      int userId, Map<String, dynamic> userData) async {
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    try {
      final updatedUser = await _userRepository.update(
        id: userId,
        fullName: userData['full_name'] as String?,
        role: userData['role'] != null
            ? _parseRole(userData['role'] as String)
            : null,
        storeId: userData['store_id'] as int?,
        isActive: userData['is_active'] as bool?,
        mustChangePassword: userData['must_change_password'] as bool?,
      );

      final userMap = _userToMap(updatedUser);
      // Stream subscription will update lists

      _isLoading = false;
      notifyListeners();
      return userMap;
    } catch (e) {
      _errorMessage = 'Failed to update user: $e';
      _isLoading = false;
      debugPrint('Error updating user: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deactivateUser(int userId) async {
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    try {
      await _userRepository.delete(userId); // Soft delete
      // Stream subscription will update lists

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to deactivate user: $e';
      _isLoading = false;
      debugPrint('Error deactivating user: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> hardDeleteUser(int userId) async {
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    try {
      await _userRepository.hardDelete(userId);
      // Stream subscription will update lists

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to delete user: $e';
      _isLoading = false;
      debugPrint('Error deleting user: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> assignUserToStore(
      int userId, int storeId) async {
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    try {
      final updatedUser = await _userRepository.update(
        id: userId,
        storeId: storeId,
      );

      final userMap = _userToMap(updatedUser);
      // Stream subscription will update lists

      _isLoading = false;
      notifyListeners();
      return userMap;
    } catch (e) {
      _errorMessage = 'Failed to assign user to store: $e';
      _isLoading = false;
      debugPrint('Error assigning user to store: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getUsersByStore(int storeId) async {
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    try {
      // Get users from local database
      final usersStream = _userRepository.watchAll(
        activeOnly: true,
        storeId: storeId,
      );

      // Get first emission
      final users = await usersStream.first;
      final userMaps = users.map((user) => _userToMap(user)).toList();

      _isLoading = false;
      notifyListeners();
      return userMaps;
    } catch (e) {
      _errorMessage = 'Failed to load users for store: $e';
      _isLoading = false;
      debugPrint('Error loading users for store: $e');
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _usersSubscription?.cancel();
    if (_storeProvider != null) {
      _storeProvider!.removeListener(_onStoreChanged);
    }
    super.dispose();
  }
}
