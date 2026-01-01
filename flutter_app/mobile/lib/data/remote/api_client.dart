import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config/env.dart';

/// Response from login endpoint
class LoginResponse {
  final String accessToken;
  final String tokenType;

  LoginResponse({
    required this.accessToken,
    required this.tokenType,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String? ?? 'bearer',
    );
  }
}

/// User information from server
class UserInfo {
  final int id;
  final String username;
  final String fullName;
  final String role;
  final int? storeId;

  UserInfo({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.storeId,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'] as int,
      username: json['username'] as String,
      fullName: json['full_name'] as String? ?? '',
      role: json['role'] as String,
      storeId: json['store_id'] as int?,
    );
  }
}

/// API client for communicating with FastAPI backend
class ApiClient {
  final String baseUrl;
  final http.Client _client;

  ApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? Env.baseUrl,
        _client = client ?? http.Client();

  /// Login with username and password
  Future<LoginResponse> login(String username, String password) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'username': username,
        'password': password,
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return LoginResponse.fromJson(data);
    } else {
      final error = jsonDecode(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: error['detail'] ?? 'Login failed',
      );
    }
  }

  /// Get user info with token
  Future<UserInfo> getUserInfo(String token) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/users/me'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return UserInfo.fromJson(data);
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch user info',
      );
    }
  }

  /// Push sync changes to server
  Future<SyncPushResponse> pushSync(List<Map<String, dynamic>> changes) async {
    // TODO: Implement after sync engine is ready
    throw UnimplementedError('pushSync not yet implemented');
  }

  /// Pull changes from server
  Future<SyncPullResponse> pullSync({required int sinceSeq}) async {
    // TODO: Implement after sync engine is ready
    throw UnimplementedError('pullSync not yet implemented');
  }
}

/// Sync push response
class SyncPushResponse {
  final List<String> applied;
  final Map<String, int> idMap;
  final List<Map<String, dynamic>> conflicts;

  SyncPushResponse({
    required this.applied,
    required this.idMap,
    required this.conflicts,
  });
}

/// Sync pull response
class SyncPullResponse {
  final List<Map<String, dynamic>> items;
  final int headSeq;

  SyncPullResponse({
    required this.items,
    required this.headSeq,
  });
}

/// API exception
class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() => 'ApiException($statusCode): $message';
}
