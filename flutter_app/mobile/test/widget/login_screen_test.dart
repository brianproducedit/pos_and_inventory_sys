import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/login_screen_redesign.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/theme/tokens.dart';

class FakeAuthProvider extends AuthProvider {
  @override
  Future<void> login(String username, String password) async {
    throw {'code': 400, 'message': 'incorrect username or password'};
  }
}

void main() {
  testWidgets('Shows friendly message and clears password on bad credentials',
      (WidgetTester tester) async {
    final fake = FakeAuthProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: fake,
        child: MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.light(primary: AppColors.primaryBrand),
          ),
          home: const LoginScreenRedesign(),
        ),
      ),
    );

    // Enter credentials
    final textFields = find.byType(TextFormField);
    expect(textFields, findsNWidgets(2));

    await tester.enterText(textFields.at(0), 'superbrian');
    await tester.enterText(textFields.at(1), 'badpassword');

    // Tap sign in
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    // Error message should be shown
    expect(find.bySemanticsLabel('login_error'), findsOneWidget);
    expect(
        find.textContaining('Incorrect username or password'), findsOneWidget);

    // Password field should be cleared and focused — verify using underlying EditableText
    final editable =
        tester.widget<EditableText>(find.byType(EditableText).at(1));
    expect(editable.controller.text, '');
    expect(editable.focusNode.hasFocus, true);
  });
}
