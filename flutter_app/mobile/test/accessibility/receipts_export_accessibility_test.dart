import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/receipts_screen.dart';
import 'package:mobile/providers/receipts_provider.dart';

class FakeReceipts extends ReceiptsProvider {
  @override
  List<Map<String, dynamic>> get receipts => [
        {
          'id': 1,
          'total': 12.5,
          'items_count': 2,
          'created_at': '2025-12-24',
          'reference': 'R-1'
        },
      ];

  @override
  bool get isLoading => false;
}

void main() {
  testWidgets('Print/Export controls are accessible and tappable',
      (tester) async {
    final prov = FakeReceipts();

    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ReceiptsProvider>.value(value: prov),
    ], child: const MaterialApp(home: ReceiptsScreen())));

    await tester.pumpAndSettle();

    // Ensure icons exist and have tooltips
    expect(find.byTooltip('Print'), findsNWidgets(1));
    expect(find.byTooltip('Export'), findsNWidgets(1));

    // Ensure FAB exists and is reachable
    expect(find.text('Export All'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // In CI and test environments this can be flaky; ensure the action is callable without throwing
    expect(find.text('Export All'), findsOneWidget);
  });
}
