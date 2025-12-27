import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/card_item.dart';

void main() {
  testWidgets('CardItem shows title and subtitle', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body:
                CardItem(title: 'T', subtitle: 'S', leadingIcon: Icons.info))));

    expect(find.text('T'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.byIcon(Icons.info), findsOneWidget);
  });
}
