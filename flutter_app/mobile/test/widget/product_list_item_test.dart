import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:mobile/widgets/product_list_item.dart';

void main() {
  testWidgets('ProductListItem uses secondaryAccent for profile circle',
      (WidgetTester tester) async {
    final product = {
      'name': 'Test Product',
      'price': 1.23,
      'stock_quantity': 5,
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductListItem(product: product, onAdd: () {}),
      ),
    ));

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundColor, equals(AppColors.secondaryAccent));
    expect(avatar.foregroundColor, equals(Colors.white));
  });
}
