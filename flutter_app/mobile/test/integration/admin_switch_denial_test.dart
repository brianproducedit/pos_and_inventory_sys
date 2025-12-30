import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../test_helpers.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/services/store_service.dart';

class _ForbiddenStoreService extends StoreService {
  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async {
    throw Exception('Failed to switch store: 403');
  }
}

void main() {
  setUp(() async {
    initializeTestHelpersOnce();
  });

  testWidgets('Admin cannot switch to another admin\'s store (backend denies)',
      (WidgetTester tester) async {
    // Arrange: admin user token and role
    SharedPreferences.setMockInitialValues({
      'access_token': 'admin-token',
      'user_role': 'admin',
      'current_store_id': 1
    });

    final provider = StoreProvider(storeService: _ForbiddenStoreService());

    // Build a minimal test widget that exposes a button to trigger the switch
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<StoreProvider>.value(value: provider),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextButton(
                key: const Key('test-switch-to-store-2'),
                onPressed: () async {
                  await provider.switchStore({'id': 2});
                },
                child: const Text('Switch to Store 2'),
              ),
              Builder(builder: (context) {
                final prov = Provider.of<StoreProvider>(context);
                return Text(prov.errorMessage ?? '',
                    key: const Key('errorText'));
              }),
            ],
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    final switchButtonFinder = find.byKey(const Key('test-switch-to-store-2'));
    expect(switchButtonFinder, findsOneWidget);

    await tester.tap(switchButtonFinder);
    await tester.pumpAndSettle();

    // Assert: provider recorded an error and UI reflects it
    expect(provider.errorMessage, contains('Failed to switch store'));
    expect(find.byKey(const Key('errorText')), findsOneWidget);
    expect(find.textContaining('Failed to switch store'), findsOneWidget);
  });
}
