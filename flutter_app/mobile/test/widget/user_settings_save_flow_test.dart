import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/user_settings_screen.dart';
import 'package:mobile/providers/settings_provider.dart';

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  bool get isLoading => false;

  String? _error;
  StoreSettings? _storeSettings = StoreSettings(businessName: 'Test Shop');
  UserSettings? _userSettings =
      UserSettings(theme: 'light', language: 'en', notificationsEnabled: true);
  SystemSettings? _systemSettings = SystemSettings(settings: {});

  @override
  String? get error => _error;

  @override
  StoreSettings? get storeSettings => _storeSettings;

  @override
  UserSettings? get userSettings => _userSettings;

  @override
  SystemSettings? get systemSettings => _systemSettings;

  @override
  Future<void> loadUserSettings() async {}

  @override
  Future<bool> updateUserSettings(UserSettings settings) async {
    _userSettings = settings;
    notifyListeners();
    return true;
  }

  @override
  Future<void> loadStoreSettings() async {}

  @override
  Future<bool> updateStoreSettings(StoreSettings settings) async {
    _storeSettings = settings;
    notifyListeners();
    return true;
  }

  @override
  Future<void> loadSystemSettings() async {}

  @override
  Future<bool> updateSystemSetting(String key, String? value) async {
    final map = Map<String, String?>.from(_systemSettings?.settings ?? {});
    map[key] = value;
    _systemSettings = SystemSettings(settings: map);
    notifyListeners();
    return true;
  }

  @override
  void clearError() {
    _error = null;
    notifyListeners();
  }
}

void main() {
  testWidgets('User Settings save flow', (tester) async {
    final prov = FakeSettingsProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider<SettingsProvider>.value(value: prov)],
      child: const MaterialApp(home: UserSettingsScreen()),
    ));

    await tester.pumpAndSettle();

    // Change theme to dark
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();

    // Save
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings saved successfully'), findsOneWidget);
  });
}
