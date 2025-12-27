import 'package:flutter/material.dart';
import '../services/user_profile_service.dart';
import 'auth_provider.dart';

class UserProfile {
  final int id;
  final String username;
  final String? fullName;
  final String role;
  final bool isActive;
  final int? storeId;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.id,
    required this.username,
    this.fullName,
    required this.role,
    required this.isActive,
    this.storeId,
    required this.createdAt,
    required this.updatedAt,
  });

  UserProfile copyWith({
    String? username,
    String? fullName,
  }) {
    return UserProfile(
      id: id,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      role: role,
      isActive: isActive,
      storeId: storeId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      username: json['username'],
      fullName: json['full_name'],
      role: json['role'],
      isActive: json['is_active'],
      storeId: json['store_id'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'full_name': fullName,
    };
  }
}

class UserProfileProvider with ChangeNotifier {
  final UserProfileService _profileService;

  UserProfileProvider({required AuthProvider authProvider})
      : _profileService = UserProfileService(authProvider: authProvider);

  UserProfile? _userProfile;
  bool _isLoading = false;
  String? _error;

  // Getters
  UserProfile? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Load user profile
  Future<void> loadUserProfile() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _profileService.getUserProfile();
      _userProfile = UserProfile.fromJson(data);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update user profile
  Future<bool> updateUserProfile(UserProfile profile) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _profileService.updateUserProfile(profile);
      _userProfile = UserProfile.fromJson(data);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Change password
  Future<bool> changePassword(
      String currentPassword, String newPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _profileService.changePassword(currentPassword, newPassword);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
