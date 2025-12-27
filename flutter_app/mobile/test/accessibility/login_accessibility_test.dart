import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/screens/login_screen_redesign.dart';
import 'package:provider/provider.dart';
import 'package:mobile/theme/tokens.dart';

// import 'store_management_accessibility_test.dart';

class TestAuth extends AuthProvider {
  @override
  Future<void> login(String username, String password) async {
    if (username == 'demo' && password == 'password') return;
    throw {'code': 'INVALID_PASSWORD'};
  }
}

void main() {
  testWidgets('Login error has semantics label and controls have adequate size',
      (tester) async {
    // Use the top-level TestAuth to avoid network calls

    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: TestAuth()),
        ],
        child: MaterialApp(
            theme: buildLightTheme(), home: const LoginScreenRedesign())));

    // Trigger validation
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    // Error texts should be visible for required fields
    expect(find.text('Required'), findsNWidgets(2));

    // The error region is not present for initial validation (field-level errors only)
    expect(find.bySemanticsLabel('login_error'), findsNothing);

    // Enter wrong credentials to trigger global friendly error
    await tester.enterText(find.byType(TextFormField).at(0), 'user');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    // Error region should now be present and announce friendly message
    expect(find.bySemanticsLabel('login_error'), findsOneWidget);
    expect(find.textContaining('Incorrect password', findRichText: true),
        findsOneWidget);

    // Ensure Sign in button and text fields have adequate tap target sizes
    final buttonFinder = find.widgetWithText(ElevatedButton, 'Sign in');
    expect(buttonFinder, findsOneWidget);
    final btnSize = tester.getSize(buttonFinder);
    expect(btnSize.height >= 48.0, true);

    final fieldFinder = find.byType(TextFormField).first;
    final fldSize = tester.getSize(fieldFinder);
    expect(fldSize.height >= 48.0, true);
  });
}
