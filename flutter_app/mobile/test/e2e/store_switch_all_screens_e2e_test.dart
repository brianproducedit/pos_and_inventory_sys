import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/inventory_provider.dart';
import 'package:mobile/providers/pos_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/services/product_service.dart';
import 'package:mobile/services/sales_service.dart';
import 'package:mobile/services/store_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      {'id': 1, 'name': 'Store A'},
      {'id': 2, 'name': 'Store B'},
    ];
  }

  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async {
    return {
      'current_store': {
        'id': storeId,
        'name': storeId == 1 ? 'Store A' : 'Store B'
      }
    };
  }

  @override
  Future<Map<String, dynamic>> getCurrentStore() async {
    return {
      'current_store': {'id': 1, 'name': 'Store A'}
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getMyStores() async {
    return [
      {'id': 1, 'name': 'Store A'},
      {'id': 2, 'name': 'Store B'},
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
          'name': 'Product A1',
          'price': 10.0,
          'stock_quantity': 100,
          'store_id': 1
        }
      ];
    } else if (storeId == 2) {
      return [
        {
          'id': 2,
          'name': 'Product B1',
          'price': 20.0,
          'stock_quantity': 50,
          'store_id': 2
        }
      ];
    }
    return [];
  }
}

class FakeSalesService extends SalesService {
  int? lastStoreId;

  @override
  Future<List<Map<String, dynamic>>> getSales(
      {int? storeId, DateTime? startDate, DateTime? endDate}) async {
    lastStoreId = storeId;
    if (storeId == 1) {
      return [
        {
          'id': 1,
          'product_name': 'Product A1',
          'quantity': 5,
          'total': 50.0,
          'created_at': DateTime.now().toIso8601String(),
          'store_id': 1
        }
      ];
    } else if (storeId == 2) {
      return [
        {
          'id': 2,
          'product_name': 'Product B1',
          'quantity': 3,
          'total': 60.0,
          'created_at': DateTime.now().toIso8601String(),
          'store_id': 2
        }
      ];
    }
    return [];
  }

  @override
  Future<Map<String, dynamic>> getSalesAnalytics(
      {int? storeId, DateTime? startDate, DateTime? endDate}) async {
    if (storeId == 1) {
      return {'total_sales': 500.0, 'total_items': 50, 'store_name': 'Store A'};
    } else if (storeId == 2) {
      return {'total_sales': 300.0, 'total_items': 30, 'store_name': 'Store B'};
    }
    return {
      'total_sales': 800.0,
      'total_items': 80,
      'store_name': 'All Stores'
    };
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'user_role': 'admin'});
  });

  group('Store Switching Across All Screens E2E', () {
    testWidgets(
        'store switching works across POS, Inventory, Sales, and Analytics screens',
        (WidgetTester tester) async {
      final fakeAuth = FakeAuthProvider();
      final storeProvider = StoreProvider(storeService: FakeStoreService());
      final posProvider = PosProvider(productService: FakeProductService());
      final inventoryProvider =
          InventoryProvider(productService: FakeProductService());
      final analyticsProvider =
          AnalyticsProvider(salesService: FakeSalesService());

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: fakeAuth),
          ChangeNotifierProvider<StoreProvider>.value(value: storeProvider),
          ChangeNotifierProvider<PosProvider>.value(value: posProvider),
          ChangeNotifierProvider<InventoryProvider>.value(
              value: inventoryProvider),
          ChangeNotifierProvider<AnalyticsProvider>.value(
              value: analyticsProvider),
        ],
        child: const app.MyApp(),
      ));

      await tester.pumpAndSettle();

      // Allow debounce and async reload
      await tester.pump(const Duration(milliseconds: 300));

      // Test POS Screen - Initial Store A (from home screen "New Sale")
      expect(find.text('New Sale'), findsOneWidget);
      await tester.tap(find.text('New Sale'));
      await tester.pumpAndSettle();
      expect(find.text('Product A1'), findsOneWidget);
      expect(find.text('Product B1'), findsNothing);

      // Switch to Store B
      await tester.tap(find.widgetWithIcon(IconButton, Icons.store));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Store B'));
      await tester.pumpAndSettle();

      // Verify POS shows Store B products
      expect(find.text('Product A1'), findsNothing);
      expect(find.text('Product B1'), findsOneWidget);

      // Test Inventory Screen (using bottom nav icon)
      await tester.tap(find.widgetWithIcon(IconButton, Icons.inventory));
      await tester.pumpAndSettle();
      expect(find.text('Product B1'), findsOneWidget);
      expect(find.text('Product A1'), findsNothing);

      // Test Sales Screen (navigate to sales history from home)
      await tester.tap(find.widgetWithIcon(IconButton, Icons.home));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sales History'));
      await tester.pumpAndSettle();
      expect(find.text('Product B1'), findsOneWidget); // Sales from Store B
      expect(find.text('Product A1'), findsNothing);

      // Test Analytics Screen (using bottom nav icon)
      await tester.tap(find.widgetWithIcon(IconButton, Icons.analytics));
      await tester.pumpAndSettle();
      expect(find.text('Store B'), findsOneWidget); // Analytics for Store B

      // Switch back to Store A
      await tester.tap(find.widgetWithIcon(IconButton, Icons.store));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Store A'));
      await tester.pumpAndSettle();

      // Verify all screens show Store A data
      await tester.tap(find.widgetWithIcon(IconButton, Icons.point_of_sale));
      await tester.pumpAndSettle();
      expect(find.text('Product A1'), findsOneWidget);
      expect(find.text('Product B1'), findsNothing);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.inventory));
      await tester.pumpAndSettle();
      expect(find.text('Product A1'), findsOneWidget);
      expect(find.text('Product B1'), findsNothing);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.home));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sales History'));
      await tester.pumpAndSettle();
      expect(find.text('Product A1'), findsOneWidget);
      expect(find.text('Product B1'), findsNothing);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.analytics));
      await tester.pumpAndSettle();
      expect(find.text('Store A'), findsOneWidget);
    });

    testWidgets('store switching to "All Stores" mode shows combined data',
        (WidgetTester tester) async {
      final fakeAuth = FakeAuthProvider();
      final storeProvider = StoreProvider(storeService: FakeStoreService());
      final posProvider = PosProvider(productService: FakeProductService());
      final inventoryProvider =
          InventoryProvider(productService: FakeProductService());
      final analyticsProvider =
          AnalyticsProvider(salesService: FakeSalesService());

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: fakeAuth),
          ChangeNotifierProvider<StoreProvider>.value(value: storeProvider),
          ChangeNotifierProvider<PosProvider>.value(value: posProvider),
          ChangeNotifierProvider<InventoryProvider>.value(
              value: inventoryProvider),
          ChangeNotifierProvider<AnalyticsProvider>.value(
              value: analyticsProvider),
        ],
        child: const app.MyApp(),
      ));

      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      // Switch to "All Stores" mode (assuming store ID 0 means all stores)
      await tester.tap(find.widgetWithIcon(IconButton, Icons.store));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'All Stores'));
      await tester.pumpAndSettle();

      // Test POS Screen shows products from all stores
      await tester.tap(find.text('POS'));
      await tester.pumpAndSettle();
      expect(find.text('Product A1'), findsOneWidget);
      expect(find.text('Product B1'), findsOneWidget);

      // Test Inventory Screen shows products from all stores
      await tester.tap(find.text('Inventory'));
      await tester.pumpAndSettle();
      expect(find.text('Product A1'), findsOneWidget);
      expect(find.text('Product B1'), findsOneWidget);

      // Test Sales Screen shows sales from all stores
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sales History'));
      await tester.pumpAndSettle();
      expect(find.text('Product A1'), findsOneWidget);
      expect(find.text('Product B1'), findsOneWidget);

      // Test Analytics Screen shows combined analytics
      await tester.tap(find.text('Analytics'));
      await tester.pumpAndSettle();
      expect(find.text('All Stores'), findsOneWidget);
    });
  });
}
