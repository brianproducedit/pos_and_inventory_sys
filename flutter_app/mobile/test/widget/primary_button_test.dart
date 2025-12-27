import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/primary_button.dart';

void main() {
  testWidgets('PrimaryButton renders and responds to tap', (tester) async {
    var pressed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PrimaryButton(
          onPressed: () {
            pressed = true;
          },
          child: const Text('Test'),
        ),
      ),
    ));

    expect(find.text('Test'), findsOneWidget);
    await tester.tap(find.text('Test'));
    expect(pressed, isTrue);
  });
}
