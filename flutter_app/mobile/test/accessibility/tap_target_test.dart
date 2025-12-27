import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/primary_button.dart';
import 'package:mobile/widgets/primary_text_field.dart';

void main() {
  testWidgets('PrimaryButton has minimum 48dp tap target', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Center(
              child:
                  PrimaryButton(onPressed: () {}, child: const Text('Tap')))),
    ));

    final finder = find.byType(ElevatedButton);
    expect(finder, findsOneWidget);

    final size = tester.getSize(finder);
    expect(size.height >= 48.0, true,
        reason: 'Button height ${size.height} is < 48');
    expect(size.width >= 48.0, true,
        reason: 'Button width ${size.width} is < 48');
  });

  testWidgets('PrimaryTextField has >=48dp height', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Center(
              child: PrimaryTextField(
                  label: 'L', controller: TextEditingController()))),
    ));

    final finder = find.byType(TextFormField);
    expect(finder, findsOneWidget);

    final size = tester.getSize(finder);
    expect(size.height >= 48.0, true,
        reason: 'TextField height ${size.height} is < 48');
  });
}
