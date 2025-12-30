import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/screens/login_screen_redesign.dart';
import 'package:provider/provider.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:mobile/services/auth_service.dart';
// import '../accessibility/store_management_accessibility_test.dart';

class TestAuth extends AuthProvider {
  @override
  Future<void> login(String username, String password) async {
    if (username == 'demo' && password == 'password') return;
    throw AuthException('INVALID_PASSWORD', 'Incorrect password');
  }
}

void main() {
  testWidgets('Login validation & error mapping', (tester) async {
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: TestAuth()),
        ],
        child: MaterialApp(
            theme: buildLightTheme(), home: const LoginScreenRedesign())));

    // Missing fields
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsNWidgets(2));

    // Enter wrong credentials
    await tester.enterText(find.byType(TextFormField).at(0), 'user');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Incorrect password', findRichText: true),
        findsOneWidget);

    // Password visibility toggle — check the EditableText which exposes obscureText
    final editableBefore =
        tester.widget<EditableText>(find.byType(EditableText).at(1));
    expect(editableBefore.obscureText, true);
    await tester.tap(find.byTooltip('Toggle password visibility'));
    await tester.pumpAndSettle();
    final editableAfter =
        tester.widget<EditableText>(find.byType(EditableText).at(1));
    expect(editableAfter.obscureText, false);

    // Enter correct credentials
    await tester.enterText(find.byType(TextFormField).at(0), 'demo');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Logged in'), findsOneWidget);
  });
}
