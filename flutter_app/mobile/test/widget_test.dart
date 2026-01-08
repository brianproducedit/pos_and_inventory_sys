// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/main.dart';
import 'package:mobile/services/data_protection_service.dart';

void main() {
  testWidgets('App builds and shows home title', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    final dataProtectionService = DataProtectionService();
    await tester
        .pumpWidget(MyApp(dataProtectionService: dataProtectionService));

    // Verify that MaterialApp has the correct title
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'POS & Inventory');
  });
}
