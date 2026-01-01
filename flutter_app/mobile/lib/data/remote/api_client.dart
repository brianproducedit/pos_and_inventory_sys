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

  // ==================== SYNC ENDPOINTS ====================

  /// Pull changes from server since last sync
  Future<Map<String, dynamic>> pullChanges({
    required String token,
    DateTime? lastSyncTime,
  }) async {
    final timestamp = lastSyncTime?.toIso8601String() ?? '';
    final url = Uri.parse('$baseUrl/api/sync/pull?since=$timestamp');
    
    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to pull changes: ${response.statusCode} ${response.body}');
    }
  }

  /// Push changes to server
  Future<Map<String, dynamic>> pushChanges({
    required String token,
    required List<Map<String, dynamic>> changes,
  }) async {
    final url = Uri.parse('$baseUrl/api/sync/push');
    
    final response = await _client.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'changes': changes}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to push changes: ${response.statusCode} ${response.body}');
    }
  }

  /// Get sync status from server
  Future<Map<String, dynamic>> getSyncStatus({required String token}) async {
    final url = Uri.parse('$baseUrl/api/sync/status');
    
    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to get sync status: ${response.statusCode}');
    }
  }

  // ==================== AUTH ENDPOINTS ====================

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

  /// Create user on server
  Future<Map<String, dynamic>> createUser({
    required String token,
    required Map<String, dynamic> userData,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/users'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(userData),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final error = jsonDecode(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: error['detail'] ?? 'Failed to create user',
      );
    }
  }

  /// Update user on server
  Future<Map<String, dynamic>> updateUser({
    required String token,
    required int userId,
    required Map<String, dynamic> userData,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/api/users/$userId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(userData),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final error = jsonDecode(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: error['detail'] ?? 'Failed to update user',
      );
    }
  }

  /// Create sale on server
  Future<Map<String, dynamic>> createSale({
    required String token,
    required Map<String, dynamic> saleData,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/sales'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(saleData),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final error = jsonDecode(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: error['detail'] ?? 'Failed to create sale',
      );
    }
  }

  /// Create product on server
  Future<Map<String, dynamic>> createProduct({
    required String token,
    required Map<String, dynamic> productData,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/products'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(productData),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final error = jsonDecode(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: error['detail'] ?? 'Failed to create product',
      );
    }
  }

  /// Update product on server
  Future<Map<String, dynamic>> updateProduct({
    required String token,
    required int productId,
    required Map<String, dynamic> productData,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/api/products/$productId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(productData),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final error = jsonDecode(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: error['detail'] ?? 'Failed to update product',
      );
    }
  }


  /// Push sync changes to server
  Future<SyncPushResponse> pushSync(List<Map<String, dynamic>> changes) async {
    // TODO: Implement batch sync endpoint when available
    throw UnimplementedError('pushSync not yet implemented');
  }

  /// Pull changes from server
  Future<SyncPullResponse> pullSync({required int sinceSeq}) async {
    // TODO: Implement delta sync endpoint when available
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
