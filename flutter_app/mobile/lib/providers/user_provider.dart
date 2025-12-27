import 'package:flutter/foundation.dart';

class UserProvider with ChangeNotifier {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get users => _users;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadUsers() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Placeholder: In real app, call backend
    await Future.delayed(const Duration(milliseconds: 50));
    _users = [];
    _isLoading = false;
    notifyListeners();
  }

  Future<void> createUser(Map<String, dynamic> user) async {
    _users.add(user);
    notifyListeners();
  }

  Future<void> updateUser(int id, Map<String, dynamic> userData) async {
    final idx = _users.indexWhere((u) => u['id'] == id);
    if (idx != -1) {
      _users[idx] = {..._users[idx], ...userData};
      notifyListeners();
    }
  }

  Future<void> deleteUser(int id) async {
    _users.removeWhere((u) => u['id'] == id);
    notifyListeners();
  }
}
