import 'dart:convert';
import 'package:drift/drift.dart';
import '../../db/app_database.dart';

/// Settings categories
enum SettingCategory {
  store, // Store-specific settings
  user, // User preferences
  system, // System configuration
  printer, // Printer settings
  payment, // Payment method settings
}

/// Repository for application settings management
/// Settings are stored in key-value format in SyncMeta table
/// Implements local-first pattern with optional sync to server
class SettingsRepository {
  final AppDatabase db;

  SettingsRepository({required this.db});

  /// Get setting value by key
  Future<String?> get(String key) async {
    final result = await (db.select(db.syncMeta)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return result?.value;
  }

  /// Get setting value with default
  Future<String> getOrDefault(String key, String defaultValue) async {
    final value = await get(key);
    return value ?? defaultValue;
  }

  /// Get setting as int
  Future<int?> getInt(String key) async {
    final value = await get(key);
    return value != null ? int.tryParse(value) : null;
  }

  /// Get setting as bool
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final value = await get(key);
    if (value == null) return defaultValue;
    return value.toLowerCase() == 'true' || value == '1';
  }

  /// Get setting as double
  Future<double?> getDouble(String key) async {
    final value = await get(key);
    return value != null ? double.tryParse(value) : null;
  }

  /// Get setting as JSON object
  Future<Map<String, dynamic>?> getJson(String key) async {
    final value = await get(key);
    if (value == null) return null;
    try {
      return jsonDecode(value) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Set setting value
  Future<void> set(String key, String value) async {
    await db.into(db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            key: key,
            value: Value(value),
          ),
        );
  }

  /// Set int value
  Future<void> setInt(String key, int value) async {
    await set(key, value.toString());
  }

  /// Set bool value
  Future<void> setBool(String key, bool value) async {
    await set(key, value.toString());
  }

  /// Set double value
  Future<void> setDouble(String key, double value) async {
    await set(key, value.toString());
  }

  /// Set JSON value
  Future<void> setJson(String key, Map<String, dynamic> value) async {
    await set(key, jsonEncode(value));
  }

  /// Delete setting
  Future<void> delete(String key) async {
    await (db.delete(db.syncMeta)..where((s) => s.key.equals(key))).go();
  }

  /// Get all settings with a prefix
  Future<Map<String, String>> getByPrefix(String prefix) async {
    final results = await (db.select(db.syncMeta)
          ..where((s) => s.key.like('$prefix%')))
        .get();

    return Map.fromEntries(
      results.map((r) => MapEntry(r.key, r.value ?? '')),
    );
  }

  /// Clear all settings with a prefix
  Future<void> clearByPrefix(String prefix) async {
    await (db.delete(db.syncMeta)..where((s) => s.key.like('$prefix%'))).go();
  }

  // ========== Store Settings ==========

  /// Get store name
  Future<String?> getStoreName() => get('store.name');

  /// Set store name
  Future<void> setStoreName(String name) => set('store.name', name);

  /// Get store address
  Future<String?> getStoreAddress() => get('store.address');

  /// Set store address
  Future<void> setStoreAddress(String address) => set('store.address', address);

  /// Get store phone
  Future<String?> getStorePhone() => get('store.phone');

  /// Set store phone
  Future<void> setStorePhone(String phone) => set('store.phone', phone);

  /// Get store currency
  Future<String> getStoreCurrency() => getOrDefault('store.currency', 'USD');

  /// Set store currency
  Future<void> setStoreCurrency(String currency) =>
      set('store.currency', currency);

  /// Get tax rate
  Future<double> getTaxRate() async {
    return await getDouble('store.tax_rate') ?? 0.0;
  }

  /// Set tax rate
  Future<void> setTaxRate(double rate) => setDouble('store.tax_rate', rate);

  /// Get low stock threshold
  Future<int> getLowStockThreshold() async {
    return await getInt('store.low_stock_threshold') ?? 10;
  }

  /// Set low stock threshold
  Future<void> setLowStockThreshold(int threshold) =>
      setInt('store.low_stock_threshold', threshold);

  // ========== Printer Settings ==========

  /// Get printer Bluetooth address
  Future<String?> getPrinterAddress() => get('printer.bluetooth_address');

  /// Set printer Bluetooth address
  Future<void> setPrinterAddress(String address) =>
      set('printer.bluetooth_address', address);

  /// Get printer name
  Future<String?> getPrinterName() => get('printer.name');

  /// Set printer name
  Future<void> setPrinterName(String name) => set('printer.name', name);

  /// Get printer paper width (mm)
  Future<int> getPrinterPaperWidth() async {
    return await getInt('printer.paper_width') ?? 58;
  }

  /// Set printer paper width
  Future<void> setPrinterPaperWidth(int width) =>
      setInt('printer.paper_width', width);

  /// Get auto-print receipt setting
  Future<bool> getAutoPrintReceipt() =>
      getBool('printer.auto_print', defaultValue: false);

  /// Set auto-print receipt
  Future<void> setAutoPrintReceipt(bool enabled) =>
      setBool('printer.auto_print', enabled);

  /// Get receipt footer text
  Future<String> getReceiptFooter() =>
      getOrDefault('printer.receipt_footer', 'Thank you for your business!');

  /// Set receipt footer text
  Future<void> setReceiptFooter(String footer) =>
      set('printer.receipt_footer', footer);

  // ========== Payment Settings ==========

  /// Get enabled payment methods
  Future<List<String>> getEnabledPaymentMethods() async {
    final value = await get('payment.enabled_methods');
    if (value == null) return ['cash', 'card', 'mobile'];
    return value.split(',');
  }

  /// Set enabled payment methods
  Future<void> setEnabledPaymentMethods(List<String> methods) =>
      set('payment.enabled_methods', methods.join(','));

  /// Get mobile payment integration (e.g., PayNow)
  Future<String?> getMobilePaymentProvider() => get('payment.mobile_provider');

  /// Set mobile payment provider
  Future<void> setMobilePaymentProvider(String provider) =>
      set('payment.mobile_provider', provider);

  // ========== User Preferences ==========

  /// Get theme mode (light, dark, system)
  Future<String> getThemeMode() => getOrDefault('user.theme_mode', 'system');

  /// Set theme mode
  Future<void> setThemeMode(String mode) => set('user.theme_mode', mode);

  /// Get language code
  Future<String> getLanguage() => getOrDefault('user.language', 'en');

  /// Set language
  Future<void> setLanguage(String languageCode) =>
      set('user.language', languageCode);

  /// Get show out-of-stock products
  Future<bool> getShowOutOfStock() =>
      getBool('user.show_out_of_stock', defaultValue: true);

  /// Set show out-of-stock products
  Future<void> setShowOutOfStock(bool show) =>
      setBool('user.show_out_of_stock', show);

  /// Get items per page for pagination
  Future<int> getItemsPerPage() async {
    return await getInt('user.items_per_page') ?? 20;
  }

  /// Set items per page
  Future<void> setItemsPerPage(int count) =>
      setInt('user.items_per_page', count);

  // ========== System Settings ==========

  /// Get last sync timestamp
  Future<DateTime?> getLastSyncTime() async {
    final value = await get('system.last_sync');
    return value != null ? DateTime.tryParse(value) : null;
  }

  /// Set last sync timestamp
  Future<void> setLastSyncTime(DateTime time) =>
      set('system.last_sync', time.toIso8601String());

  /// Get app version
  Future<String?> getAppVersion() => get('system.app_version');

  /// Set app version
  Future<void> setAppVersion(String version) =>
      set('system.app_version', version);

  /// Get database version
  Future<int> getDatabaseVersion() async {
    return await getInt('system.db_version') ?? 1;
  }

  /// Set database version
  Future<void> setDatabaseVersion(int version) =>
      setInt('system.db_version', version);

  /// Get sync enabled flag
  Future<bool> getSyncEnabled() =>
      getBool('system.sync_enabled', defaultValue: true);

  /// Set sync enabled
  Future<void> setSyncEnabled(bool enabled) =>
      setBool('system.sync_enabled', enabled);

  /// Get sync interval (minutes)
  Future<int> getSyncInterval() async {
    return await getInt('system.sync_interval') ?? 15;
  }

  /// Set sync interval
  Future<void> setSyncInterval(int minutes) =>
      setInt('system.sync_interval', minutes);

  /// Get sync only on WiFi setting
  Future<bool> getSyncOnlyOnWiFi() =>
      getBool('system.sync_only_wifi', defaultValue: false);

  /// Set sync only on WiFi
  Future<void> setSyncOnlyOnWiFi(bool enabled) =>
      setBool('system.sync_only_wifi', enabled);

  // ========== Onboarding & Setup ==========

  /// Check if app has been set up
  Future<bool> isAppSetupComplete() =>
      getBool('system.setup_complete', defaultValue: false);

  /// Mark app setup as complete
  Future<void> markSetupComplete() => setBool('system.setup_complete', true);

  /// Check if user has seen onboarding
  Future<bool> hasSeenOnboarding() =>
      getBool('user.seen_onboarding', defaultValue: false);

  /// Mark onboarding as seen
  Future<void> markOnboardingSeen() => setBool('user.seen_onboarding', true);

  // ========== Bulk Operations ==========

  /// Get all settings
  Future<Map<String, String>> getAllSettings() async {
    final results = await db.select(db.syncMeta).get();
    return Map.fromEntries(
      results.map((r) => MapEntry(r.key, r.value ?? '')),
    );
  }

  /// Export settings as JSON
  Future<Map<String, dynamic>> exportSettings() async {
    final settings = await getAllSettings();
    return {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'settings': settings,
    };
  }

  /// Import settings from JSON
  Future<void> importSettings(Map<String, dynamic> data) async {
    final settings = data['settings'] as Map<String, dynamic>;

    await db.transaction(() async {
      for (final entry in settings.entries) {
        await set(entry.key, entry.value.toString());
      }
    });
  }

  /// Reset all settings to defaults
  Future<void> resetToDefaults() async {
    await db.delete(db.syncMeta).go();

    // Set essential defaults
    await setStoreCurrency('USD');
    await setLowStockThreshold(10);
    await setThemeMode('system');
    await setLanguage('en');
    await setSyncEnabled(true);
    await setSyncInterval(15);
  }

  /// Reset settings by category
  Future<void> resetCategory(SettingCategory category) async {
    switch (category) {
      case SettingCategory.store:
        await clearByPrefix('store.');
        break;
      case SettingCategory.user:
        await clearByPrefix('user.');
        break;
      case SettingCategory.system:
        await clearByPrefix('system.');
        break;
      case SettingCategory.printer:
        await clearByPrefix('printer.');
        break;
      case SettingCategory.payment:
        await clearByPrefix('payment.');
        break;
    }
  }
}
