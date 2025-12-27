import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../providers/auth_provider.dart';
import '../config/env.dart';

class SettingsService {
  final AuthProvider authProvider;

  SettingsService({required this.authProvider});

  Future<Map<String, dynamic>> getStoreSettings() async {
    final token = await authProvider.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('${Env.baseUrl}/api/settings/store'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      debugPrint(
          'SettingsService.getStoreSettings: status=${response.statusCode} body=${response.body}');
      throw Exception(
          'Failed to load store settings: ${response.statusCode} - ${response.body}');
    }
  }

  Future<void> updateStoreSettings(dynamic settings) async {
    final token = await authProvider.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.put(
      Uri.parse('${Env.baseUrl}/api/settings/store'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(settings.toJson()),
    );

    if (response.statusCode != 200) {
      debugPrint(
          'SettingsService.updateStoreSettings: status=${response.statusCode} body=${response.body}');
      throw Exception(
          'Failed to update store settings: ${response.statusCode} - ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getUserSettings() async {
    final token = await authProvider.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('${Env.baseUrl}/api/settings/user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      debugPrint(
          'SettingsService.getUserSettings: status=${response.statusCode} body=${response.body}');
      throw Exception(
          'Failed to load user settings: ${response.statusCode} - ${response.body}');
    }
  }

  Future<void> updateUserSettings(dynamic settings) async {
    final token = await authProvider.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.put(
      Uri.parse('${Env.baseUrl}/api/settings/user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(settings.toJson()),
    );

    if (response.statusCode != 200) {
      debugPrint(
          'SettingsService.updateUserSettings: status=${response.statusCode} body=${response.body}');
      throw Exception(
          'Failed to update user settings: ${response.statusCode} - ${response.body}');
    }
  }

  Future<Map<String, String?>> getSystemSettings() async {
    final token = await authProvider.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('${Env.baseUrl}/api/settings/system'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return data.map((key, value) => MapEntry(key, value?.toString()));
    } else {
      debugPrint(
          'SettingsService.getSystemSettings: status=${response.statusCode} body=${response.body}');
      throw Exception(
          'Failed to load system settings: ${response.statusCode} - ${response.body}');
    }
  }

  Future<void> updateSystemSetting(String key, String? value) async {
    final token = await authProvider.getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.put(
      Uri.parse('${Env.baseUrl}/api/settings/system'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'key': key, 'value': value}),
    );

    if (response.statusCode != 200) {
      debugPrint(
          'SettingsService.updateSystemSetting: status=${response.statusCode} body=${response.body}');
      throw Exception(
          'Failed to update system setting: ${response.statusCode} - ${response.body}');
    }
  }
}
