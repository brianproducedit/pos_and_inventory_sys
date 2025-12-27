import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';

class TestAuthProvider extends AuthProvider {
  final String testRole;
  TestAuthProvider(this.testRole);
  @override
  String? get role => testRole;
}

Widget wrapWithRole(String role) {
  return ChangeNotifierProvider<AuthProvider>(
    create: (_) => TestAuthProvider(role),
    child: const MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppBottomNav(currentRoute: '/home'),
      ),
    ),
  );
}

void main() {
  testWidgets('AppBottomNav hides admin icons for cashier', (tester) async {
    await tester.pumpWidget(wrapWithRole('cashier'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.inventory), findsNothing);
    expect(find.byIcon(Icons.analytics), findsNothing);
    expect(find.byIcon(Icons.history), findsNothing);
    // POS should be visible
    expect(find.byIcon(Icons.point_of_sale), findsOneWidget);
  });

  testWidgets('AppBottomNav shows admin icons for admin', (tester) async {
    await tester.pumpWidget(wrapWithRole('admin'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.inventory), findsOneWidget);
    expect(find.byIcon(Icons.analytics), findsOneWidget);
    expect(find.byIcon(Icons.history), findsOneWidget);
    expect(find.byIcon(Icons.point_of_sale), findsOneWidget);
  });
}
