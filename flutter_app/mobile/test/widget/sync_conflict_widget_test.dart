import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ui/sync_demo.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/sync/sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:mobile/db/app_database.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/auth_provider.dart';

class FakeSyncService extends SyncService {
  // minimal implementation: only overrides the methods used in test
  FakeSyncService()
      : super(null, httpClient: http.Client(), serverBase: 'http://localhost');
  bool forceCalled = false;

  @override
  Future<Map<String, dynamic>> pushChanges({String? jwtToken}) async {
    return {
      'applied': [],
      'conflicts': [
        {
          'resource_type': 'product',
          'id': 1,
          'server_data': {'name': 'S', 'price': 5.0}
        }
      ],
      'id_map': {}
    };
  }

  @override
  Future<Map<String, dynamic>> forceUpdate(
      {required String resourceType,
      required int id,
      required Map<String, dynamic> data,
      String? jwtToken}) async {
    forceCalled = true;
    return {
      'applied': [
        {'resource_type': resourceType, 'operation': 'update', 'id': id}
      ],
      'conflicts': [],
      'id_map': {}
    };
  }

  @override
  Future<List<Map<String, dynamic>>> pullChanges(
      {required DateTime since,
      String types = 'products',
      String? jwtToken}) async {
    return [];
  }
}

class _TestFakeStore extends StoreProvider {
  _TestFakeStore() : super();

  @override
  Map<String, dynamic>? get currentStore => {'id': 1, 'name': 'Store 1'};

  @override
  void addListener(listener) {}

  @override
  void removeListener(listener) {}

  @override
  bool get isInitialized => true;
}

void main() {
  testWidgets('conflict dialog shown and force calls forceUpdate',
      (WidgetTester tester) async {
    final fake = FakeSyncService();
    // Provide a real temporary AppDatabase to satisfy Provider in widget
    final tmpDir = Directory.systemTemp.createTempSync('widget_test_');

    // Ensure SharedPreferences uses mocked storage for the test
    SharedPreferences.setMockInitialValues({});
    final dbPath = p.join(tmpDir.path, 'w.sqlite');
    final appDb = await AppDatabase.openWithPath(dbPath);
    addTearDown(() async {
      try {
        await appDb.close();
        final d = Directory(tmpDir.path);
        if (await d.exists()) d.deleteSync(recursive: true);
      } catch (_) {}
    });

    // Provide required providers (StoreProvider, AuthProvider) to avoid ProviderNotFound
    // and background init races. Use simple test doubles where appropriate.
    final fakeStore = _TestFakeStore();
    final auth = AuthProvider();

    await tester.pumpWidget(MaterialApp(
      home: Provider<AppDatabase>.value(
        value: appDb,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<StoreProvider>.value(value: fakeStore),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: SyncDemoScreen(syncServiceOverride: fake),
        ),
      ),
    ));

    // Ensure the test viewport is large enough so buttons are hittable
    tester.binding.window.physicalSizeTestValue = const Size(1400, 900);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(() {
      tester.binding.window.clearPhysicalSizeTestValue();
      tester.binding.window.clearDevicePixelRatioTestValue();
    });

    // Tap the Sync Now button (use ElevatedButton finder to avoid off-screen text positions)
    final syncButton = find.widgetWithText(ElevatedButton, 'Sync Now');
    expect(syncButton, findsOneWidget);
    await tester.ensureVisible(syncButton);
    await tester.tap(syncButton);
    // Allow the frame and any async actions to complete; poll until dialog appears
    await tester.pump();
    bool found = false;
    for (int i = 0; i < 20; i++) {
      if (find.text('Sync Conflict').evaluate().isNotEmpty) {
        found = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Dialog should appear
    expect(found, isTrue);

    // Also expect a conflict indicator on screen
    expect(find.text('Conflicts: 1'), findsOneWidget);

    // We already polled above and the dialog is present; proceed to tap Force from the dialog

    // Tap Force
    final forceButton = find.text('Force (admin only)');
    expect(forceButton, findsOneWidget);
    await tester.tap(forceButton);
    // Poll until the fake is called and dialog is closed (or timeout)
    bool completed = false;
    for (int i = 0; i < 30; i++) {
      if (fake.forceCalled && find.text('Sync Conflict').evaluate().isEmpty) {
        completed = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Ensure our fake was called and the dialog is closed
    expect(completed, isTrue);
    expect(fake.forceCalled, isTrue);
    expect(find.text('Sync Conflict'), findsNothing);
  });
}
