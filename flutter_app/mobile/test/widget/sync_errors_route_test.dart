import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:mobile/main.dart';
import 'package:mobile/ui/admin/sync_errors_screen.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
      'Navigating to /admin/sync-errors builds screen without ProviderScope error',
      (WidgetTester tester) async {
    // Initialize test helpers to avoid real network calls
    initializeTestHelpersOnce();

    // Use a lightweight MaterialApp for route testing to avoid full app startup
    await tester.pumpWidget(wrapWithDefaultProviders(MaterialApp(
      initialRoute: '/',
      routes: {
        '/': (context) => const Scaffold(body: SizedBox.shrink()),
        '/admin/sync-errors': (context) => const SyncErrorsScreen(),
      },
    )));
    await tester.pumpAndSettle();

    // Push the route and verify it builds
    // Use the last Navigator to avoid hitting the provider wrapper's MaterialApp navigator
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    await navigator.pushNamed('/admin/sync-errors');
    await tester.pumpAndSettle();

    expect(find.byType(SyncErrorsScreen), findsOneWidget);
  });
}
