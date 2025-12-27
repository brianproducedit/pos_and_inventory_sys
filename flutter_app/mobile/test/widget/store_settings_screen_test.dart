import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/store_settings_screen.dart';
import 'package:mobile/providers/settings_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/theme/tokens.dart';

class TestAuthAdmin extends AuthProvider {
  @override
  String? get role => 'admin';
}

class TestAuthSuper extends AuthProvider {
  @override
  String? get role => 'superadmin';
}

class TestSettingsProvider extends SettingsProvider {
  final StoreSettings? fakeStoreSettings;
  final bool _loading;
  final String? _error;

  TestSettingsProvider(
      {required AuthProvider auth,
      this.fakeStoreSettings,
      bool loading = false,
      String? error})
      : _loading = loading,
        _error = error,
        super(authProvider: auth);

  @override
  StoreSettings? get storeSettings => fakeStoreSettings;

  @override
  bool get isLoading => _loading;

  @override
  String? get error => _error;
}

void main() {
  testWidgets(
      'StoreSettingsScreen AppBar uses primaryBrand and shows Save for admin',
      (WidgetTester tester) async {
    final auth = TestAuthAdmin();
    final prov = TestSettingsProvider(
        auth: auth,
        fakeStoreSettings:
            StoreSettings(businessName: 'Test Shop', address: 'Addr'));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<SettingsProvider>.value(value: prov),
      ],
      child: const MaterialApp(home: StoreSettingsScreen()),
    ));

    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.backgroundColor, equals(AppColors.primaryBrand));
    expect(appBar.iconTheme?.color, equals(Colors.white));

    expect(
        find.widgetWithText(ElevatedButton, 'Save Settings'), findsOneWidget);
  });

  testWidgets('StoreSettingsScreen shows message for superadmin',
      (WidgetTester tester) async {
    final auth = TestAuthSuper();
    final prov = TestSettingsProvider(auth: auth, fakeStoreSettings: null);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<SettingsProvider>.value(value: prov),
      ],
      child: const MaterialApp(home: StoreSettingsScreen()),
    ));

    await tester.pumpAndSettle();

    expect(
        find.text(
            'Superadmin manages all stores and cannot edit store-specific settings.'),
        findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Save Settings'), findsNothing);
  });
}
