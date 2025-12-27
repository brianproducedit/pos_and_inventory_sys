import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/screens/receipts_screen.dart';
import '../test_helpers.dart';
import 'package:mobile/providers/receipts_provider.dart';

class TestReceiptsProvider extends ReceiptsProvider {
  @override
  List<Map<String, dynamic>> get receipts => [
        {
          'id': 1,
          'total': 12.5,
          'items_count': 2,
          'created_at': '2025-12-24',
          'reference': 'R-1'
        },
        {
          'id': 2,
          'total': 45.0,
          'items_count': 4,
          'created_at': '2025-12-23',
          'reference': 'R-2'
        },
      ];

  @override
  bool get isLoading => false;
}

void main() {
  testWidgets('Receipts screen shows receipts and actions', (tester) async {
    final prov = TestReceiptsProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ReceiptsProvider>.value(value: prov),
      ],
      child: wrapWithDefaultProviders(const ReceiptsScreen()),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Receipts'), findsOneWidget);
    expect(find.text('R-1'), findsOneWidget);
    expect(find.byTooltip('Print'), findsNWidgets(2));
    expect(find.byTooltip('Export'), findsNWidgets(2));

    // FAB is present and labeled
    expect(find.text('Export All'), findsOneWidget);

    // Tap Export All and ensure UI remains stable (FAB is tappable)
    await tester.tap(find.text('Export All'));
    await tester.pumpAndSettle();
    // Confirm receipts are still visible after tap
    expect(find.text('R-1'), findsOneWidget);
  });
}
