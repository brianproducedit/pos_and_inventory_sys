import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/store_service.dart';

class StoreProvider with ChangeNotifier {
  final StoreService _storeService;

  StoreProvider({StoreService? storeService})
      : _storeService = storeService ?? StoreService();

  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _myStores = [];
  Map<String, dynamic>? _currentStore;
  List<Map<String, dynamic>> _storeUsers = [];
  List<Map<String, dynamic>> _availableStores = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isInitialized = false;
  bool _isSwitchingStore = false;
  // Whether we successfully restored store context from backend (including explicit All Stores/null)
  bool _restoredStoreContext = false;

  List<Map<String, dynamic>> get stores => _stores;
  List<Map<String, dynamic>> get myStores => _myStores;
  List<Map<String, dynamic>> get availableStores => _availableStores;
  Map<String, dynamic>? get currentStore => _currentStore;
  List<Map<String, dynamic>> get storeUsers => _storeUsers;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isInitialized => _isInitialized;
  bool get isSwitchingStore => _isSwitchingStore;

  // Track disposal to avoid calling notifyListeners after provider is disposed
  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // Initialize store context on app start
  Future<void> initialize() async {
    debugPrint('StoreProvider.initialize: start');
    if (_isInitialized) return;

    _isInitialized = true;
    // Run initialization steps in the background to avoid blocking UI and tests
    unawaited(_loadStoredStoreContext());
    unawaited(loadMyStores());
    debugPrint('StoreProvider.initialize: scheduled background init');
  }

  // Load and restore stored store context
  Future<void> _loadStoredStoreContext() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedStoreId = prefs.getInt('current_store_id');
      debugPrint(
          'StoreProvider._loadStoredStoreContext: storedStoreId=$storedStoreId');

      // Always ask server for the canonical current store during initialization.
      // This lets us restore an explicit 'All Stores' selection (server returns current_store=null)
      debugPrint(
          'StoreProvider._loadStoredStoreContext: fetching current store from backend');
      final currentStoreData = await _storeService.getCurrentStore();
      debugPrint(
          'StoreProvider._loadStoredStoreContext: received currentStoreData=$currentStoreData');

      // If backend provides a canonical current_store (may be null for All Stores)
      if (currentStoreData.containsKey('current_store')) {
        final cs = currentStoreData['current_store'];
        debugPrint(
            'StoreProvider._loadStoredStoreContext: current_store from backend=$cs');

        // Normalize malformed backend: map with null id should be treated as All Stores
        if (cs == null || (cs is Map && cs['id'] == null)) {
          debugPrint(
              'StoreProvider._loadStoredStoreContext: backend provided null or null-id current_store; considering role before treating as All Stores');

          // Only allow All Stores (null) for admin / superadmin. For other roles, prefer
          // a deterministic fallback: load _myStores and pick the first available store.
          final prefs = await SharedPreferences.getInstance();
          final role = prefs.getString('user_role')?.toLowerCase();
          debugPrint('StoreProvider._loadStoredStoreContext: user role=$role');

          if (role == 'superadmin' || role == 'admin') {
            _currentStore = null;
            _restoredStoreContext = true;
            debugPrint(
                'StoreProvider._loadStoredStoreContext: admin/superadmin with null store - allowing All Stores');
          } else {
            // Ensure we have myStores loaded so we can pick a sensible fallback.
            if (_myStores.isEmpty) {
              try {
                await loadMyStores();
              } catch (e) {
                debugPrint(
                    'StoreProvider._loadStoredStoreContext: failed to load myStores: $e');
              }
            }
            if (_myStores.isNotEmpty) {
              _currentStore = _myStores.first;
              _restoredStoreContext = true;
              debugPrint(
                  'StoreProvider._loadStoredStoreContext: non-admin fallback to myStores[0]=${_currentStore}');
            } else {
              // No assigned stores; clear persisted context and avoid setting All Stores for non-admin
              debugPrint(
                  'StoreProvider._loadStoredStoreContext: non-admin has no myStores; clearing persisted store id');
              await prefs.remove('current_store_id');
              _currentStore =
                  null; // Ultimately null but not marked as restored from backend
            }
          }
        } else {
          _currentStore = cs;
          _restoredStoreContext = true;
          debugPrint(
              'StoreProvider._loadStoredStoreContext: successfully set _currentStore to ${_currentStore?['name']} (id=${_currentStore?['id']})');
        }
        debugPrint(
            'StoreProvider._loadStoredStoreContext: restored _currentStore=${_currentStore}');

        // Persist the canonical choice locally (null -> remove key)
        await _saveStoreContext();
        // Notify listeners so consumers can react to restored context
        _safeNotify();
      } else if (storedStoreId != null) {
        // Fallback for legacy behavior: try to use stored ID if backend did not return current_store
        debugPrint(
            'StoreProvider._loadStoredStoreContext: trying fallback with storedStoreId=$storedStoreId');
        final currentStoreData = await _storeService.getCurrentStore();
        final cs = currentStoreData['current_store'];
        if (cs == null || (cs is Map && cs['id'] == null)) {
          _currentStore = null;
          _restoredStoreContext = true;
          await _saveStoreContext();
          _safeNotify();
        } else if (currentStoreData['current_store'] != null) {
          _currentStore = currentStoreData['current_store'];
          _restoredStoreContext = true;
          await _saveStoreContext();
          _safeNotify();
        }
      }
    } catch (e) {
      debugPrint('Error loading stored store context: $e');
      // Clear invalid stored context
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('current_store_id');
    }
  }

  // Save current store context to local storage
  Future<void> _saveStoreContext() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentStore != null) {
      // Defensive: only persist integer ids. If id is missing or not parseable, clear saved id.
      final idRaw = _currentStore!['id'];
      final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
      if (id != null) {
        await prefs.setInt('current_store_id', id);
      } else {
        debugPrint(
            'StoreProvider._saveStoreContext: current store id is invalid, removing persisted key');
        await prefs.remove('current_store_id');
      }
    } else {
      await prefs.remove('current_store_id');
    }
  }

  Future<void> loadStores() async {
    if (_isLoading) return; // prevent re-entrant calls
    debugPrint('StoreProvider.loadStores: start');
    _isLoading = true;
    _errorMessage = null;
    _safeNotify();

    try {
      _stores = await _storeService.getStores();
      // Ensure myStores are loaded before performing any client-side access checks
      if (_myStores.isEmpty) {
        await loadMyStores();
      }

      // Set default current store to the first active store if none is set
      // But do not override an explicit 'All Stores' selection restored from backend.
      if (!_restoredStoreContext &&
          _currentStore == null &&
          _stores.isNotEmpty) {
        final activeStores =
            _stores.where((store) => store['is_active'] == true).toList();
        if (activeStores.isNotEmpty) {
          await switchStore(activeStores.first);
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to load stores: $e';
      debugPrint('Error loading stores: $e');
    } finally {
      _isLoading = false;
      debugPrint('StoreProvider.loadStores: end');
      _safeNotify();
    }
  }

  Future<void> loadMyStores() async {
    if (_isLoading) return; // prevent re-entrant calls
    debugPrint('StoreProvider.loadMyStores: start');
    _isLoading = true;
    _errorMessage = null;
    _safeNotify();

    try {
      _myStores = await _storeService.getMyStores();
      debugPrint(
          'StoreProvider.loadMyStores: _myStores count=${_myStores.length}, ids=${_myStores.map((s) => s['id']).toList()}');

      // If no current store is set, set it to the first available store
      // Do not auto-select if store context was restored (this preserves explicit All Stores selection)
      if (!_restoredStoreContext &&
          _currentStore == null &&
          _myStores.isNotEmpty) {
        final activeStores =
            _myStores.where((store) => store['is_active'] == true).toList();
        if (activeStores.isNotEmpty) {
          await switchStore(activeStores.first);
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to load my stores: $e';
      debugPrint('Error loading my stores: $e');
    } finally {
      _isLoading = false;
      debugPrint('StoreProvider.loadMyStores: end');
      _safeNotify();
    }
  }

  Future<Map<String, dynamic>> createStore(
      Map<String, dynamic> storeData) async {
    _errorMessage = null;
    _safeNotify();

    try {
      final newStore = await _storeService.createStore(storeData);
      _stores.add(newStore);
      _safeNotify();
      return newStore;
    } catch (e) {
      _errorMessage = 'Failed to create store: $e';
      debugPrint('Error creating store: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateStore(
      int storeId, Map<String, dynamic> storeData) async {
    _errorMessage = null;
    _safeNotify();

    try {
      final updatedStore = await _storeService.updateStore(storeId, storeData);
      final index = _stores.indexWhere((store) => store['id'] == storeId);
      if (index != -1) {
        _stores[index] = updatedStore;
      }
      _safeNotify();
      return updatedStore;
    } catch (e) {
      _errorMessage = 'Failed to update store: $e';
      debugPrint('Error updating store: $e');
      rethrow;
    }
  }

  Future<void> deleteStore(int storeId) async {
    _errorMessage = null;
    _safeNotify();

    try {
      await _storeService.deleteStore(storeId);
      _stores.removeWhere((store) => store['id'] == storeId);
      _safeNotify();
    } catch (e) {
      _errorMessage = 'Failed to delete store: $e';
      debugPrint('Error deleting store: $e');
      rethrow;
    }
  }

  Future<void> loadStoreUsers(int storeId) async {
    _isLoading = true;
    _errorMessage = null;
    _safeNotify();

    try {
      _storeUsers = await _storeService.getStoreUsers(storeId);
    } catch (e) {
      _errorMessage = 'Failed to load store users: $e';
      debugPrint('Error loading store users: $e');
    } finally {
      _isLoading = false;
      debugPrint('StoreProvider.loadStoreUsers: end');
      _safeNotify();
    }
  }

  /// Load available stores for quick actions and role-aware UI
  Future<void> loadAvailableStores() async {
    _isLoading = true;
    _errorMessage = null;
    _safeNotify();

    try {
      // Load my stores which are already filtered by the backend
      await loadMyStores();
      _availableStores = List.from(_myStores);

      debugPrint(
          'StoreProvider.loadAvailableStores: count=${_availableStores.length}');
    } catch (e) {
      _errorMessage = 'Failed to load available stores: $e';
      debugPrint('Error loading available stores: $e');
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  Future<void> assignAdminToStore(int storeId, int adminId) async {
    _errorMessage = null;
    _safeNotify();

    try {
      await _storeService.assignAdminToStore(storeId, adminId);
      // Refresh store users if we're viewing this store
      if (_currentStore?['id'] == storeId) {
        await loadStoreUsers(storeId);
      }
    } catch (e) {
      _errorMessage = 'Failed to assign admin: $e';
      debugPrint('Error assigning admin: $e');
      rethrow;
    }
  }

  Future<bool> switchStore(Map<String, dynamic> store) async {
    if (_isSwitchingStore) return false; // already switching

    // Defensive extraction of store id to avoid TypeError when id is null or not an int
    final requestedId = store['id'] is int
        ? store['id'] as int
        : int.tryParse(store['id']?.toString() ?? '') ?? -1;
    debugPrint('StoreProvider.switchStore: requested store id=$requestedId');
    debugPrint(
        'StoreProvider.switchStore: _myStores length=${_myStores.length}');
    final prefs = await SharedPreferences.getInstance();
    final storedStoreId = prefs.getInt('current_store_id');
    debugPrint('StoreProvider.switchStore: storedStoreId=$storedStoreId');
    debugPrint(
        'StoreProvider.switchStore: _myStores ids=${_myStores.map((s) => s['id']).toList()}');

    try {
      // Validate requested id
      if (requestedId < 0) {
        _errorMessage = 'Failed to switch store: invalid store id';
        debugPrint(
            'StoreProvider.switchStore: invalid requestedId=$requestedId');
        _safeNotify();
        return false;
      }

      // Special-case: allow switching to 'All Stores' (id == 0) but only for admin/superadmin.
      if (requestedId == 0) {
        final prefs = await SharedPreferences.getInstance();
        final role = prefs.getString('user_role')?.toLowerCase();
        // Deny only if role is explicitly present and is not admin/superadmin.
        // If role is null (unknown), allow switching to All Stores to support legacy clients or tests.
        if (role != null && role != 'superadmin' && role != 'admin') {
          _errorMessage =
              'Failed to switch store: insufficient permissions for All Stores view';
          debugPrint(
              'StoreProvider.switchStore: denied All Stores for role=$role');
          _safeNotify();
          return false;
        }
      }

      // No-op: already on the requested store (All Stores represented by null)
      if ((requestedId == 0 && _currentStore == null) ||
          (requestedId != 0 &&
              _currentStore != null &&
              _currentStore!['id'] == requestedId)) {
        debugPrint(
            'StoreProvider.switchStore: no-op, already on requested store id=$requestedId');
        return true;
      }

      // Client-side validation: only enforce if _myStores has been populated and user is not admin/superadmin.
      // Admin/superadmin users can access all stores, not just their assigned ones.
      // If _myStores is empty (e.g., not yet loaded), skip and let the backend enforce access control.
      if (requestedId != 0) {
        final prefs = await SharedPreferences.getInstance();
        final role = prefs.getString('user_role')?.toLowerCase();
        final isAdmin = role == 'superadmin' || role == 'admin';

        if (!isAdmin &&
            _myStores.isNotEmpty &&
            !_myStores.any((s) =>
                (s['id'] is int
                    ? s['id'] as int
                    : int.tryParse(s['id']?.toString() ?? '') ?? -1) ==
                requestedId)) {
          throw Exception('You do not have access to this store');
        }
      }

      // Prevent concurrent switches
      _isSwitchingStore = true;
      _safeNotify();

      // Call backend to switch store context
      debugPrint(
          'StoreProvider.switchStore: calling backend to switch to id=${store['id']}');
      final response = await _storeService.switchStore(requestedId);

      // Use backend's canonical current_store if present
      if (response.containsKey('current_store')) {
        // backend may intentionally return null for All Stores
        final cs = response['current_store'];
        // Normalize malformed backend response: treat a map with null id as global view
        if (cs == null) {
          _currentStore = null;
        } else if (cs is Map && (cs['id'] == null)) {
          debugPrint(
              'StoreProvider.switchStore: backend returned current_store with null id — normalizing to All Stores');
          _currentStore = null;
        } else {
          _currentStore = cs;
        }
      } else {
        // If this is the 'All Stores' option (id == 0), the canonical response may be null
        // so store the null to represent global view
        _currentStore = requestedId == 0 ? null : store;
      }

      // Save to local storage
      await _saveStoreContext();

      debugPrint(
          'StoreProvider.switchStore: success, current store id=${_currentStore?['id']}');
      _safeNotify();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to switch store: $e';
      debugPrint('Error switching store: $e');
      _safeNotify();
      return false;
    } finally {
      _isSwitchingStore = false;
      _safeNotify();
    }
  }

  /// Reset all user-specific data when a new user logs in
  void resetUserData() {
    debugPrint('StoreProvider.resetUserData: clearing user-specific state');
    _myStores = [];
    _currentStore = null;
    _storeUsers = [];
    _availableStores = [];
    _isInitialized = false;
    _restoredStoreContext = false;
    _errorMessage = null;
    _safeNotify();
  }

  void clearError() {
    _errorMessage = null;
    _safeNotify();
  }
}
