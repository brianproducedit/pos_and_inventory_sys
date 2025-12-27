import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/receipt_card.dart';
import 'package:mobile/services/time_service.dart';

void main() {
  testWidgets('ReceiptCard formats created_at using TimeService',
      (tester) async {
    // Ensure TimeService can format dates (fallback init will run if needed)
    final sampleDate = DateTime.utc(2025, 12, 24, 15, 30);
    final formatted = TimeService.instance.formatDateTime(sampleDate);

    final receipt = {
      'id': 42,
      'reference': 'R-42',
      'total': 99.99,
      'items_count': 3,
      'created_at': sampleDate,
    };

    await tester.pumpWidget(MaterialApp(home: ReceiptCard(receipt: receipt)));
    await tester.pumpAndSettle();

    // Expect the formatted date/time to appear in the subtitle text
    expect(find.textContaining(formatted), findsOneWidget);
  });
}
