import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/store_badge.dart';

void main() {
  testWidgets('StoreBadge shows All Stores when store is null',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: StoreBadge(store: null))),
    ));

    expect(find.text('Viewing: All Stores'), findsOneWidget);
    expect(find.byIcon(Icons.language), findsOneWidget);
  });

  testWidgets('StoreBadge shows All Stores when store id == 0',
      (WidgetTester tester) async {
    final storeMap = {'id': 0};

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: StoreBadge(store: storeMap))),
    ));

    expect(find.text('Viewing: All Stores'), findsOneWidget);
    expect(find.byIcon(Icons.language), findsOneWidget);
  });
}
