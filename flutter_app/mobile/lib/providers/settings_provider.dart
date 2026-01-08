import 'package:flutter/material.dart';
import '../data/repositories/settings_repository_v2.dart';

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
  final SettingsRepository _settingsRepository;

  SettingsProvider({required SettingsRepository settingsRepository})
      : _settingsRepository = settingsRepository;

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
      _storeSettings = StoreSettings(
        businessName: await _settingsRepository.get('store.business_name'),
        address: await _settingsRepository.get('store.address'),
        phone: await _settingsRepository.get('store.phone'),
        email: await _settingsRepository.get('store.email'),
        taxNumber: await _settingsRepository.get('store.tax_number'),
        receiptFooter: await _settingsRepository.get('store.receipt_footer'),
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
      if (settings.businessName != null) {
        await _settingsRepository.set(
            'store.business_name', settings.businessName!);
      }
      if (settings.address != null) {
        await _settingsRepository.set('store.address', settings.address!);
      }
      if (settings.phone != null) {
        await _settingsRepository.set('store.phone', settings.phone!);
      }
      if (settings.email != null) {
        await _settingsRepository.set('store.email', settings.email!);
      }
      if (settings.taxNumber != null) {
        await _settingsRepository.set('store.tax_number', settings.taxNumber!);
      }
      if (settings.receiptFooter != null) {
        await _settingsRepository.set(
            'store.receipt_footer', settings.receiptFooter!);
      }
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
      _userSettings = UserSettings(
        theme: await _settingsRepository.getOrDefault('user.theme', 'light'),
        language: await _settingsRepository.getOrDefault('user.language', 'en'),
        notificationsEnabled: await _settingsRepository
            .getBool('user.notifications_enabled', defaultValue: true),
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
      await _settingsRepository.set('user.theme', settings.theme);
      await _settingsRepository.set('user.language', settings.language);
      await _settingsRepository.setBool(
          'user.notifications_enabled', settings.notificationsEnabled);
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
      final data = await _settingsRepository.getByPrefix('system.');
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
      if (value != null) {
        await _settingsRepository.set('system.$key', value);
      } else {
        await _settingsRepository.delete('system.$key');
      }
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
