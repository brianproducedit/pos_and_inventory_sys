import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../providers/auth_provider.dart';
import '../config/env.dart';
import '../data/remote/postgres_api_service.dart';
import '../data/sync/postgres_sync_service.dart';
import '../data/local/database_helper.dart';

class SettingsService {
  final AuthProvider authProvider;
  final DatabaseHelper _db = DatabaseHelper();
  final PostgresSyncService _syncService;

  SettingsService(
      {required this.authProvider, PostgresSyncService? syncService})
      : _syncService = syncService ??
            PostgresSyncService(
              db: DatabaseHelper(),
              api: PostgresApiService(),
            );

  Future<Map<String, dynamic>> getStoreSettings() async {
    // Try to get from local cache first
    final currentUser = authProvider.user;
    if (currentUser?.storeId != null) {
      final localSettings = await _db.getSettings(
        settingType: 'store',
        storeId: currentUser!.storeId,
      );

      if (localSettings.isNotEmpty) {
        // Return local settings
        final settings = <String, dynamic>{};
        for (final setting in localSettings) {
          settings[setting['key']] = setting['value'];
        }
        return settings;
      }
    }

    // Fall back to server
    final token = await authProvider.getToken();
    if (token == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('${Env.baseUrl}/api/settings/store'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Cache locally
        if (currentUser?.storeId != null) {
          for (final entry in data.entries) {
            await _db.insertOrUpdateSetting(
              settingType: 'store',
              key: entry.key,
              value: entry.value.toString(),
              storeId: currentUser!.storeId,
            );
          }
        }

        return data;
      } else {
        debugPrint(
            'SettingsService.getStoreSettings: status=${response.statusCode} body=${response.body}');
        throw Exception(
            'Failed to load store settings: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('SettingsService.getStoreSettings network error: $e');
      // Return default settings if network fails
      return {};
    }
  }

  Future<void> updateStoreSettings(dynamic settings) async {
    final currentUser = authProvider.user;
    if (currentUser?.storeId == null) {
      throw Exception('User not assigned to a store');
    }

    // Update locally first (offline-first)
    if (settings is Map<String, dynamic>) {
      for (final entry in settings.entries) {
        await _db.insertOrUpdateSetting(
          settingType: 'store',
          key: entry.key,
          value: entry.value.toString(),
          storeId: currentUser!.storeId,
        );
      }
    }

    // Try to sync to server
    final token = await authProvider.getToken();
    if (token == null) throw Exception('Not authenticated');

    try {
      final response = await http.put(
        Uri.parse('${Env.baseUrl}/api/settings/store'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(settings.toJson ? settings.toJson() : settings),
      );

      if (response.statusCode != 200) {
        debugPrint(
            'SettingsService.updateStoreSettings: status=${response.statusCode} body=${response.body}');
        throw Exception(
            'Failed to update store settings: ${response.statusCode} - ${response.body}');
      }

      // Mark settings as synced
      await _syncService.syncPendingChanges();
    } catch (e) {
      debugPrint('SettingsService.updateStoreSettings network error: $e');
      // Settings are stored locally, will sync when online
      // Try to sync pending changes
      await _syncService.syncPendingChanges();
    }
  }

  Future<Map<String, dynamic>> getUserSettings() async {
    // Try to get from local cache first
    final currentUser = authProvider.user;
    if (currentUser?.id != null) {
      final localSettings = await _db.getSettings(
        settingType: 'user',
        userId: currentUser!.id,
      );

      if (localSettings.isNotEmpty) {
        // Return local settings
        final settings = <String, dynamic>{};
        for (final setting in localSettings) {
          settings[setting['key']] = setting['value'];
        }
        return settings;
      }
    }

    // Fall back to server
    final token = await authProvider.getToken();
    if (token == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('${Env.baseUrl}/api/settings/user'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Cache locally
        if (currentUser?.id != null) {
          for (final entry in data.entries) {
            await _db.insertOrUpdateSetting(
              settingType: 'user',
              key: entry.key,
              value: entry.value.toString(),
              userId: currentUser!.id,
            );
          }
        }

        return data;
      } else {
        debugPrint(
            'SettingsService.getUserSettings: status=${response.statusCode} body=${response.body}');
        throw Exception(
            'Failed to load user settings: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('SettingsService.getUserSettings network error: $e');
      // Return default settings if network fails
      return {
        'theme': 'light',
        'language': 'en',
        'notifications_enabled': true
      };
    }
  }

  Future<void> updateUserSettings(dynamic settings) async {
    final currentUser = authProvider.user;
    if (currentUser?.id == null) {
      throw Exception('User not authenticated');
    }

    // Update locally first (offline-first)
    if (settings is Map<String, dynamic>) {
      for (final entry in settings.entries) {
        await _db.insertOrUpdateSetting(
          settingType: 'user',
          key: entry.key,
          value: entry.value.toString(),
          userId: currentUser!.id,
        );
      }
    }

    // Try to sync to server
    final token = await authProvider.getToken();
    if (token == null) throw Exception('Not authenticated');

    try {
      final response = await http.put(
        Uri.parse('${Env.baseUrl}/api/settings/user'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(settings.toJson ? settings.toJson() : settings),
      );

      if (response.statusCode != 200) {
        debugPrint(
            'SettingsService.updateUserSettings: status=${response.statusCode} body=${response.body}');
        throw Exception(
            'Failed to update user settings: ${response.statusCode} - ${response.body}');
      }

      // Mark settings as synced
      await _syncService.syncPendingChanges();
    } catch (e) {
      debugPrint('SettingsService.updateUserSettings network error: $e');
      // Settings are stored locally, will sync when online
      await _syncService.syncPendingChanges();
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
