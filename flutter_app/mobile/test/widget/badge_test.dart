import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/badge.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('BadgeWidget shows label', (tester) async {
    await tester.pumpWidget(
        wrapWithDefaultProviders(Scaffold(body: BadgeWidget(label: 'NEW'))));

    expect(find.text('NEW'), findsOneWidget);
  });
}
