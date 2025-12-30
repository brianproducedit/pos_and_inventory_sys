import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/receipt_screen.dart';
import 'package:mobile/services/sales_service.dart';

class FakeSalesService extends SalesService {
  int? lastStoreId;

  @override
  Future<Map<String, dynamic>> getReceipt(int saleId, {int? storeId}) async {
    lastStoreId = storeId;
    await Future.delayed(const Duration(milliseconds: 10));
    return {
      'id': saleId,
      'sale_id': saleId,
      'created_at': DateTime.now().toIso8601String(),
      'items': [],
      'total_amount': 0.0,
      'payment_method': 'cash',
    };
  }
}

void main() {
  testWidgets('ReceiptScreen passes storeId to SalesService.getReceipt',
      (WidgetTester tester) async {
    final fake = FakeSalesService();

    await tester.pumpWidget(MaterialApp(
      home: ReceiptScreen(saleId: 123, storeId: 42, salesService: fake),
    ));

    // Allow asynchronous operations to complete
    await tester.pumpAndSettle();

    expect(fake.lastStoreId, 42);

    // Verify UI shows the sale id
    expect(find.text('Sale #123'), findsOneWidget);
  });
}
