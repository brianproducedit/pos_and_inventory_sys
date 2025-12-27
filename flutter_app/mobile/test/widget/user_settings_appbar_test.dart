import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/user_settings_screen.dart';
import 'package:mobile/theme/tokens.dart';
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
  testWidgets('UserSettingsScreen AppBar uses primaryBrand and white icons',
      (WidgetTester tester) async {
    final prov = FakeSettingsProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider<SettingsProvider>.value(value: prov)],
      child: const MaterialApp(home: UserSettingsScreen()),
    ));

    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.backgroundColor, equals(AppColors.primaryBrand));
    expect(appBar.iconTheme?.color, equals(Colors.white));

    final saveIcon = tester.widget<Icon>(find.byIcon(Icons.save).first);
    expect(saveIcon.color,
        isNull); // Icon inherits AppBar iconTheme, color may be null
  });
}
