import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/screens/pos_screen.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/pos_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/services/product_service.dart';
import 'package:mobile/services/store_service.dart';

class FakeAuthProvider extends AuthProvider {
  @override
  bool get isAuthenticated => true;

  @override
  String? get role => 'admin';
}

class FakeStoreService extends StoreService {
  @override
  Future<List<Map<String, dynamic>>> getAvailableStores() async {
    return [
      {'id': 1, 'name': 'Store 1'},
      {'id': 2, 'name': 'Store 2'},
    ];
  }

  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async {
    return {
      'current_store': {'id': storeId, 'name': 'Store $storeId'}
    };
  }

  @override
  Future<Map<String, dynamic>> getCurrentStore() async {
    return {
      'current_store': {'id': 1, 'name': 'Store 1'}
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getMyStores() async {
    // For test, admin has access to both stores
    return [
      {'id': 1, 'name': 'Store 1'},
      {'id': 2, 'name': 'Store 2'},
    ];
  }
}

class FakeProductService extends ProductService {
  int? lastStoreId;

  @override
  Future<List<Map<String, dynamic>>> getProducts({int? storeId}) async {
    lastStoreId = storeId;
    if (storeId == 1) {
      return [
        {
          'id': 1,
          'name': 'Apple',
          'price': 1.5,
          'stock_quantity': 10,
          'store_id': 1
        }
      ];
    } else if (storeId == 2) {
      return [
        {
          'id': 2,
          'name': 'Banana',
          'price': 0.5,
          'stock_quantity': 5,
          'store_id': 2
        }
      ];
    }
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'user_role': 'admin'});
  });

  testWidgets('E2E: switch store via UI and POS shows store-scoped products',
      (WidgetTester tester) async {
    final fakeAuth = FakeAuthProvider();
    final storeProvider = StoreProvider(storeService: FakeStoreService());
    final posProvider = PosProvider(productService: FakeProductService());

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: fakeAuth),
        ChangeNotifierProvider<StoreProvider>.value(value: storeProvider),
        ChangeNotifierProvider<PosProvider>.value(value: posProvider),
        // Provide analytics provider used by StoreQuickAction
        ChangeNotifierProvider(create: (_) => AnalyticsProvider()),
      ],
      child: const MaterialApp(home: PosScreen()),
    ));

    await tester.pumpAndSettle();

    // Allow debounce and async reload triggered by restored store context
    await tester.pump(const Duration(milliseconds: 300));

    // Initial products from store 1 should show
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Banana'), findsNothing);

    // Open store picker (tap the action icon)
    await tester.tap(find.widgetWithIcon(IconButton, Icons.store));
    await tester.pumpAndSettle();

    expect(find.text('Switch Store'), findsOneWidget);

    // Select Store 2 (disambiguate by tapping the SimpleDialogOption)
    await tester.tap(find.widgetWithText(SimpleDialogOption, 'Store 2'));
    await tester.pumpAndSettle();

    // After switching, POS should show Banana only
    expect(find.text('Apple'), findsNothing);
    expect(find.text('Banana'), findsOneWidget);

    // Also assert the product service received storeId==2
    final fps = posProvider.productService as FakeProductService;
    expect(fps.lastStoreId, equals(2));
  });
}
