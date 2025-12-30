import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/store_badge.dart';
import '../test_helpers.dart';

void main() {
  testWidgets('StoreBadge shows All Stores when store is null',
      (WidgetTester tester) async {
    initializeTestHelpersOnce();

    await tester.pumpWidget(wrapWithDefaultProviders(
        const Scaffold(body: Center(child: StoreBadge(store: null)))));

    await tester.pumpAndSettle();

    expect(find.text('Viewing: All Stores'), findsOneWidget);
    expect(find.byIcon(Icons.language), findsOneWidget);
  });

  testWidgets('StoreBadge shows All Stores when store id == 0',
      (WidgetTester tester) async {
    initializeTestHelpersOnce();

    final storeMap = {'id': 0};

    await tester.pumpWidget(wrapWithDefaultProviders(
        Scaffold(body: Center(child: StoreBadge(store: storeMap)))));

    await tester.pumpAndSettle();

    expect(find.text('Viewing: All Stores'), findsOneWidget);
    expect(find.byIcon(Icons.language), findsOneWidget);
  });
}
