import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ui/sync_demo.dart';
import 'package:mobile/sync/sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:mobile/db/app_database.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

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

void main() {
  testWidgets('conflict dialog shown and force calls forceUpdate',
      (WidgetTester tester) async {
    final fake = FakeSyncService();
    // Provide a real temporary AppDatabase to satisfy Provider in widget
    final tmpDir = Directory.systemTemp.createTempSync('widget_test_');
    final dbPath = p.join(tmpDir.path, 'w.sqlite');
    final appDb = await AppDatabase.openWithPath(dbPath);
    addTearDown(() async {
      try {
        await appDb.close();
        final d = Directory(tmpDir.path);
        if (await d.exists()) d.deleteSync(recursive: true);
      } catch (_) {}
    });

    await tester.pumpWidget(MaterialApp(
      home: Provider<AppDatabase>.value(
        value: appDb,
        child: SyncDemoScreen(syncServiceOverride: fake),
      ),
    ));

    // Tap the Sync Now button
    final syncButton = find.text('Sync Now');
    expect(syncButton, findsOneWidget);
    await tester.tap(syncButton);
    // Allow the frame and any async actions to complete
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    // Dialog should appear
    expect(find.text('Sync Conflict'), findsOneWidget);

    // Tap Force
    final forceButton = find.text('Force (admin only)');
    expect(forceButton, findsOneWidget);
    await tester.tap(forceButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Ensure our fake was called and the dialog is closed
    expect(fake.forceCalled, isTrue);
    expect(find.text('Sync Conflict'), findsNothing);
  });
}
