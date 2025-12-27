import 'dart:convert';
import 'package:http/http.dart' as http;
import '../providers/auth_provider.dart';
import '../config/env.dart';

class UserProfileService {
  final AuthProvider _authProvider;
  final String baseUrl = Env.baseUrl;

  UserProfileService({required AuthProvider authProvider})
      : _authProvider = authProvider;

  Future<Map<String, dynamic>> getUserProfile() async {
    final token = await _authProvider.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/users/me'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      return decoded;
    } else {
      throw Exception('Failed to load user profile: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> updateUserProfile(dynamic profile) async {
    final token = await _authProvider.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.put(
      Uri.parse('$baseUrl/api/users/me/profile'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(profile.toJson()),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['detail'] ?? 'Failed to update profile');
    }
  }

  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    final token = await _authProvider.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.put(
      Uri.parse('$baseUrl/api/users/me/password'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );

    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw Exception(errorData['detail'] ?? 'Failed to change password');
    }
  }
}
