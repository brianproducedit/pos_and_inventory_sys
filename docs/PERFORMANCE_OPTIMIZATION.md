# Performance Optimization Guide - V2 Offline-First Architecture

## Overview

This document outlines performance optimizations implemented for the V2 offline-first POS system. These optimizations ensure the app remains responsive even with large datasets and offline operation.

## Database Optimizations

### 1. Indexes

We've added strategic indexes to improve query performance:

#### Users Table
- `idx_users_username` - Fast username lookups for authentication
- `idx_users_store_id` - Efficient filtering by store
- `idx_users_sync_status` - Quick pending sync queries
- `idx_users_server_id` - Server ID lookups during sync

#### Products Table
- `idx_products_name` - Text search optimization
- `idx_products_sku` - SKU-based lookups
- `idx_products_store_id` - Store filtering
- `idx_products_sync_status` - Sync queue queries
- `idx_products_active_store` - Composite index for active products by store
- `idx_products_stock` - Low stock queries

#### Sales Table
- `idx_sales_transaction_number` - Receipt lookups
- `idx_sales_user_id` - Cashier performance reports
- `idx_sales_store_id` - Store-level analytics
- `idx_sales_created_at` - Date range queries (descending for recent-first)
- `idx_sales_sync_status` - Pending sync detection

#### Sale Items Table
- `idx_sale_items_sale_id` - Fast sale detail retrieval
- `idx_sale_items_product_id` - Product sales history

#### Sync Queue Table
- `idx_sync_queue_status` - Pending/failed item queries
- `idx_sync_queue_resource` - Resource type + ID lookups
- `idx_sync_queue_created_at` - FIFO processing order

#### Inventory Logs Table
- `idx_inventory_logs_product_id` - Product audit trails
- `idx_inventory_logs_created_at` - Recent activity queries

### 2. Query Patterns

Optimized repository methods follow these patterns:

**Prefer indexed columns in WHERE clauses:**
```dart
// Good - uses index
final users = await (select(db.users)
  ..where((u) => u.storeId.equals(storeId))
  ..where((u) => u.isActive.equals(true)))
  .get();

// Avoid - no index on fullName
final users = await (select(db.users)
  ..where((u) => u.fullName.like('%John%')))
  .get();
```

**Use LIMIT for large result sets:**
```dart
// Paginated queries
final products = await (select(db.products)
  ..orderBy([(p) => OrderingTerm.asc(p.name)])
  ..limit(50, offset: page * 50))
  .get();
```

**Batch operations when possible:**
```dart
// Process in batches instead of one-by-one
await db.batch((batch) {
  for (final item in items) {
    batch.insert(db.products, item);
  }
});
```

### 3. Sync Queue Optimization

**Exponential Backoff:**
- Failed sync items use exponential backoff: 5s, 10s, 20s, 40s, 80s
- Prevents API hammering during network issues
- Max 5 retries before marking as permanently failed

**Batch Processing:**
- Sync queue processes 100 items per cycle
- Prevents memory issues with large queues
- Allows UI to remain responsive

**Priority Queue:**
- Sales synced before inventory adjustments
- User creates before product creates
- Ensures referential integrity

## Memory Management

### 1. Stream-based UI Updates

Use `watch()` instead of `get()` for live data:
```dart
Stream<List<Product>> watchProducts() {
  return (select(db.products)
    ..where((p) => p.isActive.equals(true)))
    .watch();
}
```

### 2. Pagination

Implement pagination for large lists:
```dart
Future<List<Sale>> getSalesPaginated({
  required int page,
  int pageSize = 50,
}) async {
  return (select(db.sales)
    ..orderBy([(s) => OrderingTerm.desc(s.createdAt)])
    ..limit(pageSize, offset: page * pageSize))
    .get();
}
```

### 3. Selective Field Loading

Load only needed fields for list views:
```dart
// For list view - minimal fields
final productSummaries = await (select(db.products)
  ..where((p) => p.isActive.equals(true)))
  .map((row) => ProductSummary(
    id: row.id,
    name: row.name,
    price: row.price,
  ))
  .get();
```

## Sync Performance

### 1. Incremental Sync

Pull changes incrementally using timestamps:
```dart
// Only fetch changes since last sync
final lastSync = await getLastSyncTime();
final changes = await apiClient.pullChanges(since: lastSync);
```

### 2. Conflict Detection

Detect conflicts early to avoid unnecessary API calls:
```dart
if (local.syncStatus == SyncStatus.pending &&
    server.updatedAt > local.updatedAt) {
  // Conflict detected - mark for manual resolution
  await markAsConflict(local.id);
  return;
}
```

### 3. Parallel Sync

Sync different resource types in parallel:
```dart
await Future.wait([
  syncUsers(),
  syncProducts(),
  syncStores(),
]);
```

## UI Performance

### 1. Lazy Loading

Use lazy loading for large datasets:
```dart
class ProductListWidget extends StatefulWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: totalProducts,
      itemBuilder: (context, index) {
        // Only load visible items
        return FutureBuilder<Product>(
          future: productRepository.getById(productIds[index]),
          builder: (context, snapshot) {
            // Render product tile
          },
        );
      },
    );
  }
}
```

### 2. Debouncing

Debounce search queries:
```dart
Timer? _debounce;

void _onSearchChanged(String query) {
  _debounce?.cancel();
  _debounce = Timer(Duration(milliseconds: 300), () {
    performSearch(query);
  });
}
```

### 3. Caching

Cache frequently accessed data:
```dart
class ProductCache {
  static final Map<int, Product> _cache = {};
  static const maxAge = Duration(minutes: 5);

  static Future<Product?> get(int id) async {
    if (_cache.containsKey(id)) {
      return _cache[id];
    }
    final product = await productRepository.getById(id);
    _cache[id] = product;
    return product;
  }
}
```

## Network Optimization

### 1. Request Batching

Batch multiple operations:
```dart
// Instead of multiple API calls
await Future.wait([
  apiClient.createProduct(product1),
  apiClient.createProduct(product2),
  apiClient.createProduct(product3),
]);

// Use batch endpoint
await apiClient.batchCreateProducts([product1, product2, product3]);
```

### 2. Compression

Use gzip compression for large payloads:
```dart
final headers = {
  'Content-Encoding': 'gzip',
  'Accept-Encoding': 'gzip',
};
```

### 3. Connection Pooling

Reuse HTTP connections:
```dart
final client = IOClient(
  HttpClient()
    ..connectionTimeout = Duration(seconds: 30)
    ..maxConnectionsPerHost = 5,
);
```

## Performance Monitoring

### 1. Query Profiling

Enable SQLite query logging in debug mode:
```dart
@DriftDatabase(...)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection(logStatements: kDebugMode));
}
```

### 2. Performance Metrics

Track key metrics:
```dart
class PerformanceMetrics {
  static final Map<String, List<Duration>> _metrics = {};

  static Future<T> track<T>(String operation, Future<T> Function() fn) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      stopwatch.stop();
      _metrics.putIfAbsent(operation, () => []).add(stopwatch.elapsed);
    }
  }

  static void printReport() {
    _metrics.forEach((operation, durations) {
      final avg = durations.reduce((a, b) => a + b) / durations.length;
      print('$operation: avg ${avg.inMilliseconds}ms');
    });
  }
}
```

### 3. Memory Profiling

Monitor memory usage:
```dart
import 'dart:developer' as developer;

void checkMemory() {
  developer.Timeline.startSync('memory_check');
  // Perform operations
  developer.Timeline.finishSync();
}
```

## Best Practices

### 1. Transactions

Use transactions for atomic operations:
```dart
await db.transaction(() async {
  // All operations succeed or fail together
  await insertSale(sale);
  await insertSaleItems(items);
  await updateProductStock(productId, newStock);
});
```

### 2. Connection Management

Close database connections properly:
```dart
@override
void dispose() {
  database.close();
  super.dispose();
}
```

### 3. Background Work

Move heavy operations to background isolates:
```dart
import 'dart:isolate';

Future<List<Product>> heavyComputation(List<Product> products) async {
  return await Isolate.run(() {
    // Heavy processing here
    return processedProducts;
  });
}
```

## Performance Targets

### Query Performance
- Simple queries (by ID): < 10ms
- Filtered queries: < 50ms
- Full-text search: < 100ms
- Complex joins: < 200ms

### Sync Performance
- Pull 100 changes: < 2s
- Push 50 changes: < 3s
- Conflict detection: < 100ms per item

### UI Responsiveness
- List scroll: 60 FPS
- Search debounce: 300ms
- Navigation: < 100ms

## Monitoring in Production

### 1. Analytics

Track performance metrics:
```dart
Analytics.trackTiming(
  category: 'database',
  variable: 'product_search',
  time: duration.inMilliseconds,
);
```

### 2. Error Reporting

Log slow queries:
```dart
if (duration > Duration(seconds: 1)) {
  Logger.warn('Slow query detected', {
    'query': queryString,
    'duration': duration.inMilliseconds,
  });
}
```

### 3. User Feedback

Show loading indicators for operations > 500ms:
```dart
if (operation.expectedDuration > Duration(milliseconds: 500)) {
  showLoadingIndicator();
}
```

## Future Optimizations

1. **Incremental Search** - Build search index for instant results
2. **Query Cache** - LRU cache for frequently accessed queries
3. **Background Sync** - Offload sync to background isolate
4. **Compression** - Compress local database using SQLite's built-in compression
5. **Virtual Scrolling** - Implement virtual list for 10,000+ items

---

**Last Updated:** January 1, 2026  
**Version:** 2.0  
**Maintained By:** Development Team
