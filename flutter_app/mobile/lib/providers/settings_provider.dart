import 'package:flutter/material.dart';
import '../data/sync/postgres_sync_service.dart';
import '../services/settings_service.dart';
import 'auth_provider.dart';

class StoreSettings {
  final String? businessName;
  final String? address;
  final String? phone;
  final String? email;
  final String? taxNumber;
  final String? receiptFooter;

  StoreSettings({
    this.businessName,
    this.address,
    this.phone,
    this.email,
    this.taxNumber,
    this.receiptFooter,
  });

  StoreSettings copyWith({
    String? businessName,
    String? address,
    String? phone,
    String? email,
    String? taxNumber,
    String? receiptFooter,
  }) {
    return StoreSettings(
      businessName: businessName ?? this.businessName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      taxNumber: taxNumber ?? this.taxNumber,
      receiptFooter: receiptFooter ?? this.receiptFooter,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'business_name': businessName,
      'address': address,
      'phone': phone,
      'email': email,
      'tax_number': taxNumber,
      'receipt_footer': receiptFooter,
    };
  }
}

class UserSettings {
  final String theme;
  final String language;
  final bool notificationsEnabled;

  UserSettings({
    this.theme = 'light',
    this.language = 'en',
    this.notificationsEnabled = true,
  });

  UserSettings copyWith({
    String? theme,
    String? language,
    bool? notificationsEnabled,
  }) {
    return UserSettings(
      theme: theme ?? this.theme,
      language: language ?? this.language,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'theme': theme,
      'language': language,
      'notifications_enabled': notificationsEnabled,
    };
  }
}

class SystemSettings {
  final Map<String, String?> settings;

  SystemSettings({required this.settings});

  SystemSettings copyWith({Map<String, String?>? settings}) {
    return SystemSettings(settings: settings ?? this.settings);
  }
}

class SettingsProvider with ChangeNotifier {
  final SettingsService _settingsService;

  SettingsProvider(
      {required AuthProvider authProvider, PostgresSyncService? syncService})
      : _settingsService = SettingsService(
            authProvider: authProvider, syncService: syncService);

  StoreSettings? _storeSettings;
  UserSettings? _userSettings;
  SystemSettings? _systemSettings;

  bool _isLoading = false;
  String? _error;

  // Getters
  StoreSettings? get storeSettings => _storeSettings;
  UserSettings? get userSettings => _userSettings;
  SystemSettings? get systemSettings => _systemSettings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Load store settings
  Future<void> loadStoreSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _settingsService.getStoreSettings();
      _storeSettings = StoreSettings(
        businessName: data['business_name'],
        address: data['address'],
        phone: data['phone'],
        email: data['email'],
        taxNumber: data['tax_number'],
        receiptFooter: data['receipt_footer'],
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update store settings
  Future<bool> updateStoreSettings(StoreSettings settings) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _settingsService.updateStoreSettings(settings);
      _storeSettings = settings;
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

  // Load user settings
  Future<void> loadUserSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _settingsService.getUserSettings();
      _userSettings = UserSettings(
        theme: data['theme'] ?? 'light',
        language: data['language'] ?? 'en',
        notificationsEnabled: data['notifications_enabled'] ?? true,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update user settings
  Future<bool> updateUserSettings(UserSettings settings) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _settingsService.updateUserSettings(settings);
      _userSettings = settings;
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

  // Load system settings (superadmin only)
  Future<void> loadSystemSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _settingsService.getSystemSettings();
      _systemSettings = SystemSettings(settings: data);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update system setting (superadmin only)
  Future<bool> updateSystemSetting(String key, String? value) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _settingsService.updateSystemSetting(key, value);
      if (_systemSettings != null) {
        final updatedSettings =
            Map<String, String?>.from(_systemSettings!.settings);
        updatedSettings[key] = value;
        _systemSettings = SystemSettings(settings: updatedSettings);
      }
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
