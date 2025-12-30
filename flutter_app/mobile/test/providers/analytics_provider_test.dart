import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/services/sales_service.dart';

class FakeSalesService extends SalesService {
  int? lastStoreId;

  @override
  Future<Map<String, dynamic>> getSalesAnalytics({int? storeId}) async {
    lastStoreId = storeId;
    return {
      'total_sales': 0,
      'total_revenue': 0.0,
      'average_sale': 0.0,
      'daily_sales': [],
      'recent_sales': [],
      'top_products': [],
      'inventory_alerts': [],
    };
  }
}

class FakeStoreProvider extends StoreProvider {
  final Map<String, dynamic>? _store;
  FakeStoreProvider(this._store) : super();

  @override
  Map<String, dynamic>? get currentStore => _store;
}

void main() {
  test('AnalyticsProvider parses string-typed currentStore id', () async {
    final fakeSvc = FakeSalesService();
    final analytics = AnalyticsProvider(salesService: fakeSvc);

    // Simulate a store provider that reports the id as a string
    final fakeStore = FakeStoreProvider({'id': '2', 'name': 'StoreString'});

    analytics.setStoreProvider(fakeStore);

    // Trigger the change notification
    fakeStore.notifyListeners();

    // allow async work to complete
    await Future.delayed(const Duration(milliseconds: 50));

    expect(fakeSvc.lastStoreId, equals(2));
  });
}
