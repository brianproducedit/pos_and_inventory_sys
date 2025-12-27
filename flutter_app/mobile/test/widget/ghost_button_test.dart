import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/ghost_button.dart';

void main() {
  testWidgets('GhostButton renders and responds to tap', (tester) async {
    var pressed = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GhostButton(
                onPressed: () {
                  pressed = true;
                },
                child: const Text('Ghost')))));

    expect(find.text('Ghost'), findsOneWidget);
    await tester.tap(find.text('Ghost'));
    expect(pressed, isTrue);
  });
}
