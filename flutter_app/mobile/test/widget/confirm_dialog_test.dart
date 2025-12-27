import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/confirm_dialog.dart';

void main() {
  testWidgets('ConfirmDialog returns true when confirmed', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              final result =
                  await showConfirmDialog(context, title: 'T', content: 'C');
              // Show a SnackBar to surface result for testing
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(result.toString())));
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Confirm
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('true'), findsOneWidget);
  });
}
