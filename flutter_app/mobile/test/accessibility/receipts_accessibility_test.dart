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
  testWidgets('Receipts accessible and shows header', (tester) async {
    final prov = FakeReceipts();

    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ReceiptsProvider>.value(value: prov),
    ], child: const MaterialApp(home: ReceiptsScreen())));

    await tester.pumpAndSettle();

    expect(find.text('Receipts'), findsOneWidget);
    expect(find.text('R-1'), findsOneWidget);
  });
}
