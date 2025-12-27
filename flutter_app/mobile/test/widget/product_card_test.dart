import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/product_card.dart';

void main() {
  testWidgets('ProductCard shows info and triggers add', (tester) async {
    var pressed = false;
    final product = {
      'id': 1,
      'name': 'Test',
      'price': 9.5,
      'stock_quantity': 3
    };

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProductCard(
                product: product,
                onAdd: () {
                  pressed = true;
                }))));

    expect(find.text('Test'), findsOneWidget);
    expect(find.text('\$9.50'), findsOneWidget);
    expect(find.text('Stock: 3'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(pressed, isTrue);
  });
}
