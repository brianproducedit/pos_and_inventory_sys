import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/settings_screen.dart';
import 'package:mobile/ui/admin/sync_errors_screen.dart';
import 'package:mobile/domain/models/sync_error.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import '../test_helpers.dart';

void main() {
  initializeTestHelpersOnce();

  testWidgets('Settings shows Sync Errors and navigates to screen',
      (WidgetTester tester) async {
    final auth = TestAuthProvider(roleValue: 'admin');

    final testError = SyncError(
      id: 1,
      queueId: 10,
      tableName: 'products',
      rowId: 42,
      error: 'Conflict',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<StoreProvider>.value(value: TestStoreProvider()),
      ],
      child: MaterialApp(
        routes: {
          '/admin/sync-errors': (context) =>
              SyncErrorsScreen(testErrors: [testError])
        },
        home: const SettingsScreen(),
      ),
    ));

    await tester.pumpAndSettle();

    // Ensure the Sync Errors card is present
    expect(find.text('Sync Errors'), findsOneWidget);

    // Tap the card and verify navigation shows the conflict text
    await tester.tap(find.text('Sync Errors'));
    await tester.pumpAndSettle();

    expect(find.text('Conflict'), findsOneWidget);
  });
}
