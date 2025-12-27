import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/toast.dart';

void main() {
  testWidgets('showToast displays a SnackBar', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showToast(context, 'Hello'),
            child: const Text('Toast'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Toast'));
    await tester.pump();

    expect(find.text('Hello'), findsOneWidget);
  });
}
