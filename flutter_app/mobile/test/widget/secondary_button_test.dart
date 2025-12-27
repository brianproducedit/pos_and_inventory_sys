import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/secondary_button.dart';

void main() {
  testWidgets('SecondaryButton renders and responds to tap', (tester) async {
    var pressed = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SecondaryButton(
                onPressed: () {
                  pressed = true;
                },
                child: const Text('Sec')))));

    expect(find.text('Sec'), findsOneWidget);
    await tester.tap(find.text('Sec'));
    expect(pressed, isTrue);
  });
}
