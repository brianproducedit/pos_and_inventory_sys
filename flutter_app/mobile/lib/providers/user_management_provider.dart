import 'dart:async';

import 'package:flutter/foundation.dart';
import '../services/user_management_service.dart';
import 'store_provider.dart';

class UserManagementProvider with ChangeNotifier {
  final UserManagementService _userService = UserManagementService();

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _admins = [];
  List<Map<String, dynamic>> _cashiers = [];
  bool _isLoading = false;
  String? _errorMessage;
  StoreProvider? _storeProvider;
  int? _lastStoreId;

  void _onStoreChanged() {
    final newId = _storeProvider?.currentStore?['id'] as int?;
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
    _lastStoreId = _storeProvider?.currentStore?['id'] as int?;
    _storeProvider!.addListener(_onStoreChanged);
  }

  Future<void> loadUsers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Check if we have store context and user role to determine filtering
      if (_storeProvider?.currentStore != null) {
        final currentStoreId = _storeProvider!.currentStore!['id'];
        _users = await _userService.getUsersByStore(currentStoreId);
      } else {
        // Fallback to all users (for superadmin or when no store context)
        _users = await _userService.getUsers();
      }

      _admins = _users.where((user) => user['role'] == 'admin').toList();
      _cashiers = _users.where((user) => user['role'] == 'cashier').toList();
    } catch (e) {
      _errorMessage = 'Failed to load users: $e';
      debugPrint('Error loading users: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    try {
      final newUser = await _userService.createUser(userData);
      _users.add(newUser);

      // Update appropriate list
      if (newUser['role'] == 'admin') {
        _admins.add(newUser);
      } else if (newUser['role'] == 'cashier') {
        _cashiers.add(newUser);
      }

      _isLoading = false;
      notifyListeners();
      return newUser;
    } catch (e) {
      _errorMessage = 'Failed to create user: $e';
      _isLoading = false;
      debugPrint('Error creating user: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateUser(
      int userId, Map<String, dynamic> userData) async {
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    try {
      final updatedUser = await _userService.updateUser(userId, userData);

      // Update in main users list
      final userIndex = _users.indexWhere((user) => user['id'] == userId);
      if (userIndex != -1) {
        _users[userIndex] = updatedUser;

        // Update in role-specific lists
        if (updatedUser['role'] == 'admin') {
          final adminIndex = _admins.indexWhere((user) => user['id'] == userId);
          if (adminIndex != -1) {
            _admins[adminIndex] = updatedUser;
          } else {
            _admins.add(updatedUser);
          }
          _cashiers.removeWhere((user) => user['id'] == userId);
        } else if (updatedUser['role'] == 'cashier') {
          final cashierIndex =
              _cashiers.indexWhere((user) => user['id'] == userId);
          if (cashierIndex != -1) {
            _cashiers[cashierIndex] = updatedUser;
          } else {
            _cashiers.add(updatedUser);
          }
          _admins.removeWhere((user) => user['id'] == userId);
        } else {
          // For other roles, remove from both lists
          _admins.removeWhere((user) => user['id'] == userId);
          _cashiers.removeWhere((user) => user['id'] == userId);
        }
      }

      _isLoading = false;
      notifyListeners();
      return updatedUser;
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
      await _userService.deactivateUser(userId);

      // Remove from all lists (soft delete)
      _users.removeWhere((user) => user['id'] == userId);
      _admins.removeWhere((user) => user['id'] == userId);
      _cashiers.removeWhere((user) => user['id'] == userId);

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
      await _userService.hardDeleteUser(userId);

      // Remove from all lists (hard delete)
      _users.removeWhere((user) => user['id'] == userId);
      _admins.removeWhere((user) => user['id'] == userId);
      _cashiers.removeWhere((user) => user['id'] == userId);

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
      final updatedUser = await _userService.assignUserToStore(userId, storeId);

      // Update user in lists
      final userIndex = _users.indexWhere((user) => user['id'] == userId);
      if (userIndex != -1) {
        _users[userIndex] = updatedUser;

        // Update in role-specific lists
        if (updatedUser['role'] == 'admin') {
          final adminIndex = _admins.indexWhere((user) => user['id'] == userId);
          if (adminIndex != -1) {
            _admins[adminIndex] = updatedUser;
          }
        } else if (updatedUser['role'] == 'cashier') {
          final cashierIndex =
              _cashiers.indexWhere((user) => user['id'] == userId);
          if (cashierIndex != -1) {
            _cashiers[cashierIndex] = updatedUser;
          }
        }
      }

      _isLoading = false;
      notifyListeners();
      return updatedUser;
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
      final users = await _userService.getUsersByStore(storeId);
      _isLoading = false;
      notifyListeners();
      return users;
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
    if (_storeProvider != null) {
      _storeProvider!.removeListener(_onStoreChanged);
    }
    super.dispose();
  }
}
