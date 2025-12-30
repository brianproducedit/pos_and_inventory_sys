import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/sales_history_screen.dart';
import 'package:mobile/services/sales_service.dart';
import 'package:mobile/services/store_service.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSalesService extends SalesService {
  int? lastStoreId;

  @override
  Future<List<Map<String, dynamic>>> getSales({int? storeId}) async {
    lastStoreId = storeId;
    return [];
  }
}

class _FakeStoreService extends StoreService {
  @override
  Future<Map<String, dynamic>> switchStore(int storeId) async => {
        'current_store': {'id': storeId}
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SalesHistory uses StoreProvider currentStore for cashier',
      (WidgetTester tester) async {
    final fake = FakeSalesService();
    final storeProvider = StoreProvider(storeService: _FakeStoreService());
    SharedPreferences.setMockInitialValues({});
    final ok = await storeProvider.switchStore({'id': 5});
    print(
        'DEBUG: switchStore returned $ok, currentStore=${storeProvider.currentStore}');
    expect(ok, true);

    final auth = AuthProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<StoreProvider>.value(value: storeProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(home: SalesHistoryScreen(salesService: fake)),
    ));

    await tester.pumpAndSettle();

    // fake.lastStoreId should be 5
    expect(fake.lastStoreId, 5);
  });

  testWidgets('SalesHistory requests global data when admin on All Stores',
      (WidgetTester tester) async {
    final fake = FakeSalesService();
    final storeProvider = StoreProvider();

    SharedPreferences.setMockInitialValues({'user_role': 'admin'});

    // simulate admin and allow All Stores
    await storeProvider.switchStore({'id': 0});

    final auth = AuthProvider();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<StoreProvider>.value(value: storeProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(home: SalesHistoryScreen(salesService: fake)),
    ));

    await tester.pumpAndSettle();

    // fake.lastStoreId should be null for All Stores
    expect(fake.lastStoreId, null);
  });
}
