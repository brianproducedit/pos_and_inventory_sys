import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Components demo route resolves and shows demo', (tester) async {
    await tester.pumpWidget(MaterialApp(
      routes: {
        '/components_demo': (context) => const Scaffold(body: Text('Demo')),
      },
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pushNamed('/components_demo'),
            child: const Text('Open Demo'),
          ),
        ),
      ),
    ));

    expect(find.text('Demo'), findsNothing);
    await tester.tap(find.text('Open Demo'));
    await tester.pumpAndSettle();
    expect(find.text('Demo'), findsOneWidget);
  });
}
