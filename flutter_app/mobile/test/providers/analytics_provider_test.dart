import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/data/repositories/analytics_repository_v2.dart' as v2;
import 'package:mobile/data/repositories/store_repository_v2.dart';
import 'package:mobile/db/app_database.dart';

class FakeAnalyticsRepository extends v2.AnalyticsRepository {
  int? lastStoreId;
  DateTime? lastStartDate;
  DateTime? lastEndDate;

  FakeAnalyticsRepository(super.db);

  @override
  Future<v2.SalesSummary> getSalesSummary({
    int? storeId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    lastStoreId = storeId;
    lastStartDate = startDate;
    lastEndDate = endDate;
    return v2.SalesSummary(
      totalSales: 0,
      totalRevenue: 0.0,
      averageOrderValue: 0.0,
      cashSales: 0,
      cardSales: 0,
      mobileSales: 0,
      startDate: startDate ?? DateTime.now(),
      endDate: endDate ?? DateTime.now(),
    );
  }

  @override
  Future<List<v2.TopProduct>> getTopProducts({
    int? storeId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 10,
  }) async {
    return [];
  }

  @override
  Future<List<Sale>> getRecentSales({
    int? storeId,
    int limit = 10,
  }) async {
    return [];
  }

  @override
  Future<List<Product>> getLowStockProducts({
    int? storeId,
    int threshold = 10,
  }) async {
    return [];
  }

  @override
  Future<List<v2.SalesByPeriod>> getSalesByPeriod({
    int? storeId,
    DateTime? startDate,
    DateTime? endDate,
    String granularity = 'day',
  }) async {
    return [];
  }
}

class MockStoreRepository extends StoreRepository {
  MockStoreRepository(AppDatabase db) : super(db);
}

class FakeStoreProvider extends StoreProvider {
  final Map<String, dynamic>? _store;
  FakeStoreProvider(this._store, AppDatabase db)
      : super(storeRepository: MockStoreRepository(db));

  @override
  Map<String, dynamic>? get currentStore => _store;
}

void main() {
  test('AnalyticsProvider parses string-typed currentStore id', () async {
    final db = AppDatabase();
    final fakeRepo = FakeAnalyticsRepository(db);
    final analytics = AnalyticsProvider(analyticsRepository: fakeRepo);

    // Simulate a store provider that reports the id as a string
    final fakeStore = FakeStoreProvider({'id': '2', 'name': 'StoreString'}, db);

    analytics.setStoreProvider(fakeStore);

    // Trigger the change notification
    fakeStore.notifyListeners();

    // allow async work to complete
    await Future.delayed(const Duration(milliseconds: 100));

    expect(fakeRepo.lastStoreId, equals(2));

    await db.close();
  });
}
