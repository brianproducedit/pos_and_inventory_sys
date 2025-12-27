import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:mobile/screens/settings_screen.dart';
import '../test_helpers.dart';

void main() {
  testWidgets('SettingsScreen AppBar uses primaryBrand color',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrapWithDefaultProviders(const SettingsScreen()));

    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.backgroundColor, equals(AppColors.primaryBrand));
    expect(appBar.iconTheme?.color, equals(Colors.white));

    // Leading icons (profile and user settings) should use primaryBrand
    final accountIcon =
        tester.widget<Icon>(find.byIcon(Icons.account_circle).first);
    expect(accountIcon.color, equals(AppColors.primaryBrand));
    final personIcon = tester.widget<Icon>(find.byIcon(Icons.person).first);
    expect(personIcon.color, equals(AppColors.primaryBrand));

    // Trailing chevron should also use primaryBrand
    final chevron = tester.widget<Icon>(find.byIcon(Icons.chevron_right).first);
    expect(chevron.color, equals(AppColors.primaryBrand));
  });
}
