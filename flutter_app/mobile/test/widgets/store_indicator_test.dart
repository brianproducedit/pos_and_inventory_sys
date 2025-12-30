import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/widgets/store_badge.dart';
import 'package:mobile/providers/auth_provider.dart';

class FakeAuth extends AuthProvider {
  final String roleValue;
  FakeAuth(this.roleValue);

  @override
  String? get role => roleValue;
}

void main() {
  testWidgets('StoreIndicator shows All Stores for admin', (tester) async {
    final auth = FakeAuth('admin');

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(
        home: Scaffold(appBar: AppBar(title: StoreIndicator(store: null))),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.textContaining('Viewing: All Stores'), findsOneWidget);
    expect(find.textContaining('limited'), findsNothing);
  });

  testWidgets('StoreIndicator shows limited message for non-admin',
      (tester) async {
    final auth = FakeAuth('cashier');

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(
        home: Scaffold(appBar: AppBar(title: StoreIndicator(store: null))),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.textContaining('Viewing: All Stores (limited access)'),
        findsOneWidget);
  });
}
