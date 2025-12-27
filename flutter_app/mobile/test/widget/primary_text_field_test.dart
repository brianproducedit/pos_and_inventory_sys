import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/primary_text_field.dart';

void main() {
  testWidgets('PrimaryTextField shows label and validates', (tester) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Form(
          key: formKey,
          child: PrimaryTextField(
            controller: controller,
            label: 'Email',
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
        ),
      ),
    ));

    expect(find.text('Email'), findsOneWidget);
    // Trigger validation
    formKey.currentState!.validate();
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'a@b.com');
    formKey.currentState!.validate();
    await tester.pump();
    expect(find.text('Required'), findsNothing);
  });
}
