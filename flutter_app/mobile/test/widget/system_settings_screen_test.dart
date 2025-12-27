import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/system_settings_screen.dart';
import 'package:mobile/providers/settings_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/theme/tokens.dart';

class TestAuth extends AuthProvider {
  @override
  String? get role => 'superadmin';
}

class TestSettingsProvider extends SettingsProvider {
  final Map<String, String?> _settings;
  TestSettingsProvider(
      {required AuthProvider auth, Map<String, String?>? settings})
      : _settings = settings ?? {},
        super(authProvider: auth);

  @override
  SystemSettings? get systemSettings => SystemSettings(settings: _settings);

  @override
  bool get isLoading => false;
}

void main() {
  testWidgets('SystemSettingsScreen AppBar uses primaryBrand color',
      (WidgetTester tester) async {
    final auth = TestAuth();
    final prov = TestSettingsProvider(auth: auth, settings: {
      'default_currency': 'ZWL',
      'timezone': 'Africa/Harare',
    });

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<SettingsProvider>.value(value: prov),
      ],
      child: const MaterialApp(home: SystemSettingsScreen()),
    ));

    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.backgroundColor, equals(AppColors.primaryBrand));
    expect(appBar.iconTheme?.color, equals(Colors.white));
  });
}
