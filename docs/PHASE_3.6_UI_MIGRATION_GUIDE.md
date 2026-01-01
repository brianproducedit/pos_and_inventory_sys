# Phase 3.6: UI Migration Guide - Wire V2 Repositories to Screens

**Status:** In Progress  
**Goal:** Replace all V1 API-dependent services with V2 offline-first repositories

---

## Overview

Phase 3.6 involves migrating existing UI screens from V1 architecture (direct API calls via services) to V2 architecture (local-first repositories with background sync).

### Migration Pattern

**V1 (Old):**
```dart
// Direct API call - UI blocks on network
final products = await ProductService().getProducts(storeId: store.id);
setState(() => _products = products);
```

**V2 (New):**
```dart
// Read from local DB - UI never blocks
final productsStream = ProductRepository_v2(db).watchAll(storeId: store.id);
StreamBuilder<List<Product>>(
  stream: productsStream,
  builder: (context, snapshot) => ListView(...),
);
```

---

## Services to Replace

### 1. ProductService → ProductRepository_v2 ✅
**File:** `lib/services/product_service.dart`  
**Status:** READY TO REPLACE  
**Repository:** `lib/data/repositories/product_repository_v2.dart`

**Methods to Migrate:**
- `getProducts()` → `watchAll()` or `getAll()`
- `getAllProducts()` → `getAll(includeInactive: true)`
- `createProduct()` → `create()`
- `updateProduct()` → `update()`
- `deleteProduct()` → `delete()` or `deactivate()`

**Affected Screens:**
- [x] `inventory_screen.dart`
- [x] `add_product_screen.dart`
- [x] `edit_product_screen.dart`
- [x] `pos_screen.dart`

### 2. StoreService → StoreRepository_v2 ✅
**File:** `lib/services/store_service.dart`  
**Status:** READY TO REPLACE  
**Repository:** `lib/data/repositories/store_repository_v2.dart`

**Methods to Migrate:**
- `getStores()` → `watchAll()` or `getAll()`
- `createStore()` → `create()`
- `updateStore()` → `update()`
- `deleteStore()` → `delete()`
- `assignStore()` → `assignUserToStore()`

**Affected Screens:**
- [x] `store_management_screen.dart`
- [x] `store_settings_screen.dart`
- [x] `home_screen.dart` (store selector)

### 3. UserService → UserRepository_v2 ✅
**Status:** NO V1 SERVICE EXISTS  
**Repository:** `lib/data/repositories/user_repository_v2.dart`

**Methods Available:**
- `create()` - Create user with ghost user support
- `getAll()` - Get all users
- `getByStore()` - Filter by store
- `getByRole()` - Filter by role
- `update()` - Update user info
- `changePassword()` - Change password
- `deactivate()` / `activate()` - User status management

**Affected Screens:**
- [x] `user_management_screen.dart`
- [x] `cashier_management_screen.dart`
- [x] `admin_management_screen.dart`
- [x] `user_profile_screen.dart`
- [x] `store_users_screen.dart`

### 4. SaleService → SaleRepository_v2 ✅
**Status:** NO V1 SERVICE EXISTS  
**Repository:** `lib/data/repositories/sale_repository_v2.dart`

**Methods Available:**
- `completeSale()` - Complete sale with atomic transaction
- `getAll()` - Get all sales
- `getByStore()` - Filter by store
- `getByUser()` - Filter by user
- `getByDateRange()` - Date range query
- `getTotalRevenue()` - Analytics
- `getSalesCount()` - Analytics

**Affected Screens:**
- [x] `pos_screen.dart` (checkout)
- [x] `sales_history_screen.dart`
- [x] `analytics_screen.dart`
- [x] `receipt_screen.dart`

---

## Migration Strategy

### Step 1: Identify API Call Points

Search for patterns:
```bash
# Find ProductService usage
grep -r "ProductService()" flutter_app/mobile/lib/screens/

# Find StoreService usage
grep -r "StoreService()" flutter_app/mobile/lib/screens/

# Find direct API calls
grep -r "http.get\|http.post" flutter_app/mobile/lib/screens/
```

### Step 2: Replace with Repository Pattern

#### Example: Inventory Screen

**Before (V1):**
```dart
class InventoryScreen extends StatefulWidget {
  @override
  _InventoryScreenState createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final ProductService _productService = ProductService();
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    try {
      final products = await _productService.getProducts(
        storeId: Provider.of<StoreProvider>(context, listen: false).currentStoreId,
      );
      setState(() {
        _products = products;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load products: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return CircularProgressIndicator();
    return ListView.builder(
      itemCount: _products.length,
      itemBuilder: (context, index) => ProductTile(_products[index]),
    );
  }
}
```

**After (V2):**
```dart
class InventoryScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context, listen: false);
    final repo = ProductRepository_v2(db);
    final storeId = Provider.of<StoreProvider>(context).currentStoreId;

    return StreamBuilder<List<Product>>(
      stream: repo.watchAll(storeId: storeId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorWidget(snapshot.error);
        }
        
        if (!snapshot.hasData) {
          return CircularProgressIndicator();
        }

        final products = snapshot.data!;
        
        if (products.isEmpty) {
          return EmptyState(
            icon: Icons.inventory_2,
            title: 'No products found',
            message: 'Add your first product to get started',
          );
        }

        return ListView.builder(
          itemCount: products.length,
          itemBuilder: (context, index) => ProductTile(products[index]),
        );
      },
    );
  }
}
```

#### Example: Add Product Screen

**Before (V1):**
```dart
Future<void> _saveProduct() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() => _saving = true);
  try {
    await _productService.createProduct({
      'name': _nameController.text,
      'price': double.parse(_priceController.text),
      'stock_quantity': int.parse(_stockController.text),
    });
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Product created successfully')),
    );
  } catch (e) {
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to create product: $e')),
    );
  }
}
```

**After (V2):**
```dart
Future<void> _saveProduct() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() => _saving = true);
  try {
    final db = Provider.of<AppDatabase>(context, listen: false);
    final repo = ProductRepository_v2(db);
    final storeId = Provider.of<StoreProvider>(context, listen: false).currentStoreId;

    await repo.create(
      name: _nameController.text,
      price: double.parse(_priceController.text),
      stockQuantity: int.parse(_stockController.text),
      storeId: storeId!,
    );

    if (!mounted) return;
    context.showSuccess('Product created successfully');
    Navigator.pop(context);
  } catch (e) {
    if (!mounted) return;
    context.showError(ErrorHandler.getFriendlyMessage(e));
  } finally {
    if (mounted) setState(() => _saving = false);
  }
}
```

### Step 3: Update Providers

Ensure providers use repositories instead of services:

**Before (V1):**
```dart
class POSProvider with ChangeNotifier {
  final ProductService _productService = ProductService();
  
  Future<void> loadProducts() async {
    _products = await _productService.getProducts();
    notifyListeners();
  }
}
```

**After (V2):**
```dart
class POSProvider with ChangeNotifier {
  final ProductRepository_v2 _productRepo;
  StreamSubscription? _productSubscription;
  
  POSProvider(this._productRepo) {
    _subscribeToProducts();
  }
  
  void _subscribeToProducts() {
    _productSubscription = _productRepo.watchAll().listen((products) {
      _products = products;
      notifyListeners();
    });
  }
  
  @override
  void dispose() {
    _productSubscription?.cancel();
    super.dispose();
  }
}
```

### Step 4: Inject Dependencies

Update main.dart to provide repositories:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database
  final db = await AppDatabase.open();
  
  runApp(
    MultiProvider(
      providers: [
        // Database
        Provider<AppDatabase>.value(value: db),
        
        // Repositories
        Provider<ProductRepository_v2>(
          create: (_) => ProductRepository_v2(db),
        ),
        Provider<StoreRepository_v2>(
          create: (_) => StoreRepository_v2(db),
        ),
        Provider<UserRepository_v2>(
          create: (_) => UserRepository_v2(db),
        ),
        Provider<SaleRepository_v2>(
          create: (_) => SaleRepository_v2(db),
        ),
        Provider<InventoryRepository_v2>(
          create: (_) => InventoryRepository_v2(db),
        ),
        Provider<SettingsRepository_v2>(
          create: (_) => SettingsRepository_v2(db),
        ),
        
        // Providers (using repositories)
        ChangeNotifierProvider<AuthProvider>(
          create: (context) => AuthProvider(
            context.read<UserRepository_v2>(),
            context.read<SettingsRepository_v2>(),
          ),
        ),
        ChangeNotifierProvider<POSProvider>(
          create: (context) => POSProvider(
            context.read<ProductRepository_v2>(),
            context.read<SaleRepository_v2>(),
          ),
        ),
        // ... other providers
      ],
      child: MyApp(),
    ),
  );
}
```

---

## Screen-by-Screen Migration Checklist

### High Priority (Core Functionality)

#### ✅ Inventory Management
- [ ] **inventory_screen.dart**
  - Replace `ProductService().getProducts()` with `ProductRepository_v2.watchAll()`
  - Use StreamBuilder for reactive updates
  - Handle empty states and errors
  
- [ ] **add_product_screen.dart**
  - Replace `ProductService().createProduct()` with `ProductRepository_v2.create()`
  - Use ErrorHandler for user feedback
  - Remove try-catch network error handling (repository handles it)
  
- [ ] **edit_product_screen.dart**
  - Replace `ProductService().updateProduct()` with `ProductRepository_v2.update()`
  - Watch single product with `watchById()`
  - Handle product not found cases

#### ✅ POS/Checkout
- [ ] **pos_screen.dart**
  - Replace `ProductService().getProducts()` with `ProductRepository_v2.watchAll()`
  - Use `CartProvider` (already V2-ready)
  - Integrate with `SaleRepository_v2.completeSale()`
  - Print receipt with `ReceiptModel.generate()`

#### ✅ Sales History
- [ ] **sales_history_screen.dart**
  - Use `SaleRepository_v2.watchByDateRange()`
  - Filter by store/user with repository methods
  - Real-time updates via streams

#### ✅ User Management
- [ ] **user_management_screen.dart**
  - Use `UserRepository_v2.watchAll()`
  - Create users with `UserRepository_v2.create()` (ghost user support)
  - Update users with `UserRepository_v2.update()`
  
- [ ] **cashier_management_screen.dart**
  - Use `UserRepository_v2.getByRole(UserRole.cashier)`
  - Filter by store with `getByStore()`
  
- [ ] **admin_management_screen.dart**
  - Use `UserRepository_v2.getByRole(UserRole.admin)`
  
- [ ] **user_profile_screen.dart**
  - Use `UserRepository_v2.watchById()`
  - Password changes with `UserRepository_v2.changePassword()`

#### ✅ Store Management
- [ ] **store_management_screen.dart**
  - Use `StoreRepository_v2.watchAll()`
  - Create/update/delete with repository methods
  
- [ ] **store_settings_screen.dart**
  - Use `SettingsRepository_v2` for store preferences
  
- [ ] **home_screen.dart**
  - Store selector using `StoreRepository_v2.watchAll()`

### Medium Priority (Enhanced Features)

#### ✅ Analytics
- [ ] **analytics_screen.dart**
  - Use `SaleRepository_v2.getTotalRevenue()`
  - Use `SaleRepository_v2.getSalesCount()`
  - Date range queries with `getByDateRange()`

#### ✅ Settings
- [ ] **user_settings_screen.dart**
  - Use `SettingsRepository_v2` for user preferences
  
- [ ] **system_settings_screen.dart**
  - Use `SettingsRepository_v2` for system config

### Low Priority (Supporting Features)

#### ✅ Audit & Logs
- [ ] **audit_logs_screen.dart**
  - Use `InventoryRepository_v2.getAuditTrail()`
  - Watch inventory changes with streams

---

## Testing Strategy

### Unit Tests
- [x] Repository unit tests (already complete in Phase 7.1)

### Integration Tests
- [ ] Test screen with mocked repository
- [ ] Verify StreamBuilder updates correctly
- [ ] Test error handling flow

### E2E Tests
- [ ] Complete user workflow offline
- [ ] Verify data persists across app restarts
- [ ] Test sync after connectivity restored

---

## Common Pitfalls

### ❌ Don't: Await Stream Data
```dart
// WRONG - streams are not awaitable
final products = await repo.watchAll();
```

### ✅ Do: Use StreamBuilder
```dart
// CORRECT
StreamBuilder<List<Product>>(
  stream: repo.watchAll(),
  builder: (context, snapshot) => ...,
)
```

### ❌ Don't: Use setState with Streams
```dart
// WRONG - unnecessary state management
repo.watchAll().listen((products) {
  setState(() => _products = products);
});
```

### ✅ Do: Let StreamBuilder Handle It
```dart
// CORRECT - StreamBuilder manages state
StreamBuilder<List<Product>>(
  stream: repo.watchAll(),
  builder: (context, snapshot) => buildUI(snapshot.data),
)
```

### ❌ Don't: Block UI on Save
```dart
// WRONG - shows loading indicator during save
setState(() => _saving = true);
await repo.create(...);
setState(() => _saving = false);
```

### ✅ Do: Show Instant Feedback
```dart
// CORRECT - optimistic UI
await repo.create(...); // Returns immediately (writes to local DB)
context.showSuccess('Product created'); // Instant feedback
// Sync happens in background automatically
```

---

## Migration Progress Tracking

**Screens Migrated:** 0 / 27  
**Progress:** 0%

### Current Status

**Not Started:**
- All 27 screens pending migration

**In Progress:**
- None

**Complete:**
- None

---

## Next Steps

1. Start with high-priority screens (inventory, POS, sales)
2. Migrate providers to use repositories
3. Update dependency injection in main.dart
4. Test each screen after migration
5. Remove old V1 services after all screens migrated

---

**Last Updated:** January 1, 2026  
**Assigned To:** Development Team  
**Target Completion:** Week 8
